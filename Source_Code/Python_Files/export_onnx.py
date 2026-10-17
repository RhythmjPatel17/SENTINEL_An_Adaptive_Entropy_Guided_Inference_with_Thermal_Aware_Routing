import argparse

import torch

from models import build_mobilenetv2, build_mobilenetv3

def export(args):
    model = (build_mobilenetv3(pretrained=False) if args.model == "m1"
              else build_mobilenetv2(pretrained=False))
    state = torch.load(args.ckpt, map_location="cpu")
    model.load_state_dict(state)
    model.eval()

    dummy = torch.randn(1, 3, args.resolution, args.resolution)
    torch.onnx.export(
        model, dummy, args.out,
        input_names=["input"], output_names=["logits"],
        dynamic_axes={"input": {0: "batch"}, "logits": {0: "batch"}},
        opset_version=17,
    )
    print(f"Exported {args.model} -> {args.out}")

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--ckpt", required=True)
    p.add_argument("--model", choices=["m1", "m2"], required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--resolution", type=int, default=224)
    args = p.parse_args()
    export(args)
