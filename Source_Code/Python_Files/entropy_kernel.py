import numpy as np
import pycuda.driver as cuda
from pycuda.compiler import SourceModule

_KERNEL_SRC = r"""
extern "C" __global__
void fused_entropy_confidence(const float* logits, int num_classes,
                               float* entropy_out, float* confidence_out)
{

    extern __shared__ float shmem[];
    float* probs = shmem;
    float* reduce_buf = shmem + num_classes;

    int tid = threadIdx.x;

    float local_max = -1e30f;
    for (int i = tid; i < num_classes; i += blockDim.x)
        local_max = fmaxf(local_max, logits[i]);
    reduce_buf[tid] = local_max;
    __syncthreads();
    for (int s = blockDim.x / 2; s > 0; s >>= 1) {
        if (tid < s) reduce_buf[tid] = fmaxf(reduce_buf[tid], reduce_buf[tid + s]);
        __syncthreads();
    }
    float max_logit = reduce_buf[0];
    __syncthreads();

    float local_sum = 0.0f;
    for (int i = tid; i < num_classes; i += blockDim.x) {
        float e = expf(logits[i] - max_logit);
        probs[i] = e;
        local_sum += e;
    }
    reduce_buf[tid] = local_sum;
    __syncthreads();
    for (int s = blockDim.x / 2; s > 0; s >>= 1) {
        if (tid < s) reduce_buf[tid] += reduce_buf[tid + s];
        __syncthreads();
    }
    float sum_exp = reduce_buf[0];
    __syncthreads();

    float local_h = 0.0f;
    for (int i = tid; i < num_classes; i += blockDim.x) {
        float p = probs[i] / sum_exp;
        probs[i] = p;
        local_h += -p * logf(fmaxf(p, 1e-12f));
    }
    reduce_buf[tid] = local_h;
    __syncthreads();
    for (int s = blockDim.x / 2; s > 0; s >>= 1) {
        if (tid < s) reduce_buf[tid] += reduce_buf[tid + s];
        __syncthreads();
    }

    if (tid == 0) {
        float H = reduce_buf[0];
        entropy_out[0] = H;
        confidence_out[0] = 1.0f - H / logf((float)num_classes);
    }
}

"""

_module = None
_kernel_fn = None

def _get_kernel():
    global _module, _kernel_fn
    if _kernel_fn is None:
        _module = SourceModule(_KERNEL_SRC, no_extern_c=True)
        _kernel_fn = _module.get_function("fused_entropy_confidence")
    return _kernel_fn

def launch_entropy_kernel(d_logits_ptr, num_classes: int, d_entropy_ptr, d_confidence_ptr, stream):
    kernel = _get_kernel()
    threads = min(128, max(32, 1 << (num_classes - 1).bit_length()))
    shared_bytes = 2 * num_classes * 4
    kernel(
        d_logits_ptr, np.int32(num_classes), d_entropy_ptr, d_confidence_ptr,
        block=(threads, 1, 1), grid=(1, 1), shared=shared_bytes, stream=stream,
    )
