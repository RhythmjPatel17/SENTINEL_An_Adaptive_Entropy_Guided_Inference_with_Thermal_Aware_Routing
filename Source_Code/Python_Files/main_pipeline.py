import argparse
import csv
import glob
import os

from PIL import Image

from hierarchical_inference import FPGAPipeline, GPUPipeline

def read_gpu_power_w(default: float = 9.0) -> float:
    return default

def read_fpga_power_w(default: float = 4.0) -> float:
    return default

def energy_delay_product(power_w: float, latency_ms: float) -> float:
    dt_s = latency_ms / 1000.0
    return power_w * (dt_s ** 2) * 1000.0

def run_batch(args):
    image_paths = sorted(
        glob.glob(os.path.join(args.image_dir, "*.png"))
        + glob.glob(os.path.join(args.image_dir, "*.jpg"))
    )
    if not image_paths:
        raise FileNotFoundError(f"No .png/.jpg images found under {args.image_dir}")

    if args.backend == "gpu":
        pipeline = GPUPipeline(args.m1_ckpt, args.m2_ckpt)
        power_fn = lambda: read_gpu_power_w(args.gpu_power_w)
    else:
        from fpga_interface import SentinelFPGADriverPynq
        driver = SentinelFPGADriverPynq(bitstream_path=args.bitstream)
        pipeline = FPGAPipeline(driver)
        power_fn = lambda: read_fpga_power_w(args.fpga_power_w)

    rows = []
    for path in image_paths:
        img = Image.open(path).convert("RGB")
        result = pipeline.run(img, t_junction_c=args.t_junction)

        power = power_fn()
        edp = energy_delay_product(power, result.total_latency_ms)
        energy_j = power * result.total_latency_ms / 1000.0

        row = {
            "file": os.path.basename(path),
            "model_selected": result.model_selected,
            "predicted_class": result.predicted_class,
            "entropy_H": round(result.entropy, 3),
            "confidence_pct": round(result.confidence * 100, 1),
            "threshold_tau": round(result.threshold, 3),
            f"{args.backend}_latency_ms": round(result.total_latency_ms, 2),
            f"{args.backend}_power_w": power,
            f"{args.backend}_energy_J": round(energy_j, 3),
            "edp_mJs": round(edp, 3),
            "t_junction_c": args.t_junction,
        }
        rows.append(row)
        print(row)

    with open(args.out, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"\nWrote {len(rows)} rows -> {args.out}")

    m1_count = sum(1 for r in rows if r["model_selected"] == "M1")
    print(f"M1 termination rate: {m1_count / len(rows) * 100:.1f}% "
          f"(paper reports 71.4%); M2 escalation rate: "
          f"{100 - m1_count / len(rows) * 100:.1f}% (paper reports 28.6%)")

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--m1_ckpt", help="required for --backend gpu")
    p.add_argument("--m2_ckpt", help="required for --backend gpu")
    p.add_argument("--bitstream", default="sentinel.bit", help="used for --backend fpga")
    p.add_argument("--image_dir", required=True)
    p.add_argument("--backend", choices=["gpu", "fpga"], default="gpu")
    p.add_argument("--t_junction", type=float, default=60.0)
    p.add_argument("--gpu_power_w", type=float, default=9.0)
    p.add_argument("--fpga_power_w", type=float, default=4.0)
    p.add_argument("--out", default="results.csv")
    args = p.parse_args()
    run_batch(args)
