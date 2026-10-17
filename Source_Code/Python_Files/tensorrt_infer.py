import argparse
import time

import numpy as np

try:
    import pycuda.autoinit
    import pycuda.driver as cuda
    import tensorrt as trt
except ImportError as e:
    raise ImportError(
        "tensorrt_infer.py must run on the Jetson Orin Nano with JetPack's "
        "TensorRT and pycuda installed. On x86 dev machines, use models.py / "
        "PyTorch for functional testing instead."
    ) from e

from cuda_entropy_kernel import launch_entropy_kernel

TRT_LOGGER = trt.Logger(trt.Logger.WARNING)

def build_engine(onnx_path: str, engine_path: str, fp16: bool = True, max_batch: int = 1):
    builder = trt.Builder(TRT_LOGGER)
    network = builder.create_network(1 << int(trt.NetworkDefinitionCreationFlag.EXPLICIT_BATCH))
    parser = trt.OnnxParser(network, TRT_LOGGER)

    with open(onnx_path, "rb") as f:
        if not parser.parse(f.read()):
            for i in range(parser.num_errors):
                print(parser.get_error(i))
            raise RuntimeError(f"Failed to parse ONNX file {onnx_path}")

    config = builder.create_builder_config()
    config.set_memory_pool_limit(trt.MemoryPoolType.WORKSPACE, 1 << 28)
    if fp16 and builder.platform_has_fast_fp16:
        config.set_flag(trt.BuilderFlag.FP16)

    profile = builder.create_optimization_profile()
    input_tensor = network.get_input(0)
    shape = input_tensor.shape
    profile.set_shape(input_tensor.name, (1, *shape[1:]), (1, *shape[1:]), (max_batch, *shape[1:]))
    config.add_optimization_profile(profile)

    serialized = builder.build_serialized_network(network, config)
    if serialized is None:
        raise RuntimeError("Engine build failed.")
    with open(engine_path, "wb") as f:
        f.write(serialized)
    print(f"Built TensorRT engine -> {engine_path}")

class TRTRunner:
    def __init__(self, engine_path: str):
        with open(engine_path, "rb") as f, trt.Runtime(TRT_LOGGER) as runtime:
            self.engine = runtime.deserialize_cuda_engine(f.read())
        self.context = self.engine.create_execution_context()

        self.input_name = self.engine.get_tensor_name(0)
        self.output_name = self.engine.get_tensor_name(1)
        self.input_shape = self.engine.get_tensor_shape(self.input_name)
        self.output_shape = self.engine.get_tensor_shape(self.output_name)

        self.stream = cuda.Stream()
        self.d_input = cuda.mem_alloc(int(np.prod(self.input_shape[1:])) * 4 * 8)
        self.d_output = cuda.mem_alloc(int(np.prod(self.output_shape[1:])) * 4 * 8)
        self.d_entropy = cuda.mem_alloc(4)
        self.d_conf = cuda.mem_alloc(4)

    def infer(self, x: np.ndarray):
        x = np.ascontiguousarray(x, dtype=np.float32)
        self.context.set_input_shape(self.input_name, x.shape)

        t0 = time.time()
        cuda.memcpy_htod_async(self.d_input, x, self.stream)
        self.context.set_tensor_address(self.input_name, int(self.d_input))
        self.context.set_tensor_address(self.output_name, int(self.d_output))
        self.context.execute_async_v3(self.stream.handle)

        num_classes = int(self.output_shape[-1])
        logits = np.empty((1, num_classes), dtype=np.float32)
        cuda.memcpy_dtoh_async(logits, self.d_output, self.stream)

        h_out = np.empty(1, dtype=np.float32)
        c_out = np.empty(1, dtype=np.float32)
        launch_entropy_kernel(self.d_output, num_classes, self.d_entropy, self.d_conf, self.stream)
        cuda.memcpy_dtoh_async(h_out, self.d_entropy, self.stream)
        cuda.memcpy_dtoh_async(c_out, self.d_conf, self.stream)

        self.stream.synchronize()
        latency_ms = (time.time() - t0) * 1000.0

        probs = np.exp(logits - logits.max()) / np.exp(logits - logits.max()).sum()
        return {
            "probs": probs[0],
            "entropy": float(h_out[0]),
            "confidence": float(c_out[0]),
            "latency_ms": latency_ms,
        }

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--onnx", default=None)
    p.add_argument("--engine", required=True)
    p.add_argument("--build", action="store_true")
    p.add_argument("--image", default=None)
    args = p.parse_args()

    if args.build:
        assert args.onnx, "--onnx required with --build"
        build_engine(args.onnx, args.engine)

    if args.image:
        from PIL import Image
        runner = TRTRunner(args.engine)
        img = Image.open(args.image).convert("RGB").resize((224, 224))
        arr = (np.asarray(img).astype(np.float32) / 127.5) - 1.0
        arr = arr.transpose(2, 0, 1)[None, ...]
        result = runner.infer(arr)
        print(result)
