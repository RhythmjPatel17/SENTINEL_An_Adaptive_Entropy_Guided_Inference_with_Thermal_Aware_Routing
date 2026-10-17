import argparse
import time
from dataclasses import dataclass, field
from typing import Optional

import numpy as np
import torch
from PIL import Image
from torchvision import transforms

from entropy_utils import normalized_confidence, shannon_entropy
from models import WM811K_CLASSES, build_mobilenetv2, build_mobilenetv3
from thermal_governor import ThermalGovernor

@dataclass
class InferenceResult:
    predicted_class: str
    model_selected: str
    entropy: float
    confidence: float
    threshold: float
    total_latency_ms: float
    stage_latency: dict = field(default_factory=dict)

class GPUPipeline:
    def __init__(self, m1_ckpt: str, m2_ckpt: str, device: str = "cuda"):
        self.device = torch.device(device if torch.cuda.is_available() else "cpu")
        self.governor = ThermalGovernor()

        self.m1 = build_mobilenetv3(pretrained=False).to(self.device).eval()
        self.m1.load_state_dict(torch.load(m1_ckpt, map_location=self.device))
        self.m2 = build_mobilenetv2(pretrained=False).to(self.device).eval()
        self.m2.load_state_dict(torch.load(m2_ckpt, map_location=self.device))

        self.normalize = transforms.Normalize(mean=[0.5] * 3, std=[0.5] * 3)

    def _preprocess(self, img: Image.Image, resolution: int) -> torch.Tensor:
        tfm = transforms.Compose([
            transforms.Resize((resolution, resolution)),
            transforms.ToTensor(),
            self.normalize,
        ])
        return tfm(img).unsqueeze(0).to(self.device)

    @torch.no_grad()
    def _run_model(self, model, x: torch.Tensor) -> np.ndarray:
        logits = model(x)
        return torch.softmax(logits, dim=-1).squeeze(0).cpu().numpy()

    def run(self, img: Image.Image, t_junction_c: float, resolution: int = 224) -> InferenceResult:
        t_start = time.time()
        stage_latency = {}

        tau = self.governor.threshold(t_junction_c)

        t0 = time.time()
        x = self._preprocess(img, resolution)
        stage_latency["preprocess_ms"] = (time.time() - t0) * 1000

        t0 = time.time()
        p1 = self._run_model(self.m1, x)
        stage_latency["m1_ms"] = (time.time() - t0) * 1000

        t0 = time.time()
        H = shannon_entropy(p1)
        c = normalized_confidence(p1)
        route_to_m2 = c < tau
        stage_latency["entropy_route_ms"] = (time.time() - t0) * 1000

        if not route_to_m2:
            pred_idx = int(np.argmax(p1))
            model_used = "M1"
        else:
            t0 = time.time()
            p2 = self._run_model(self.m2, x)
            stage_latency["m2_ms"] = (time.time() - t0) * 1000
            pred_idx = int(np.argmax(p2))
            model_used = "M2"

        total_latency_ms = (time.time() - t_start) * 1000
        return InferenceResult(
            predicted_class=WM811K_CLASSES[pred_idx],
            model_selected=model_used,
            entropy=H,
            confidence=c,
            threshold=tau,
            total_latency_ms=total_latency_ms,
            stage_latency=stage_latency,
        )

class FPGAPipeline:
    def __init__(self, fpga_driver, image_hw: int = 224):
        self.driver = fpga_driver
        self.image_hw = image_hw

    def run(self, img: Image.Image, t_junction_c: float) -> InferenceResult:
        img_resized = img.convert("RGB").resize((self.image_hw, self.image_hw))
        arr = np.asarray(img_resized, dtype=np.uint8)

        result = self.driver.classify_image(arr, t_junction_c)
        return InferenceResult(
            predicted_class=result["predicted_class"],
            model_selected=result["model_selected"],
            entropy=result["entropy"],
            confidence=result["confidence"],
            threshold=result["threshold"],
            total_latency_ms=result["fpga_latency_ms"],
            stage_latency={"fpga_cycle_accurate_ms": result["fpga_latency_ms"],
                            "wall_clock_ms": result["wall_latency_ms"]},
        )

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--m1_ckpt", help="required for --backend gpu")
    p.add_argument("--m2_ckpt", help="required for --backend gpu")
    p.add_argument("--image", required=True)
    p.add_argument("--t_junction", type=float, default=60.0)
    p.add_argument("--backend", choices=["gpu", "fpga"], default="gpu")
    p.add_argument("--bitstream", default="sentinel.bit", help="required for --backend fpga")
    args = p.parse_args()

    img = Image.open(args.image).convert("RGB")

    if args.backend == "gpu":
        assert args.m1_ckpt and args.m2_ckpt, "--m1_ckpt/--m2_ckpt required for GPU backend"
        pipeline = GPUPipeline(args.m1_ckpt, args.m2_ckpt)
        result = pipeline.run(img, t_junction_c=args.t_junction)
    else:
        from fpga_interface import SentinelFPGADriverPynq
        driver = SentinelFPGADriverPynq(bitstream_path=args.bitstream)
        pipeline = FPGAPipeline(driver)
        result = pipeline.run(img, t_junction_c=args.t_junction)

    print(result)
