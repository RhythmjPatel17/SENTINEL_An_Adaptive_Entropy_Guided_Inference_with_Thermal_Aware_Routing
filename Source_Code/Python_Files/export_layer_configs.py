import argparse
import struct
from dataclasses import dataclass
from typing import List

import numpy as np
import torch
import torch.nn as nn

from models import build_mobilenetv2, build_mobilenetv3

LT_POINTWISE, LT_DEPTHWISE, LT_SE, LT_STANDARD3x3, LT_AVGPOOL, LT_FC = range(6)
ACT_NONE, ACT_RELU6, ACT_HSWISH, ACT_HSIGMOID = range(4)

@dataclass
class LayerDesc:
    ltype: int
    act: int
    in_h: int
    in_w: int
    in_ch: int
    out_ch: int
    kernel: int
    stride: int
    use_residual: bool
    weight_offset: int
    requant_mult: int
    requant_shift: int

    def pack(self) -> bytes:
        return struct.pack(
            "<BBHHHHBBBIHB",
            self.ltype, self.act, self.in_h, self.in_w, self.in_ch, self.out_ch,
            self.kernel, self.stride, int(self.use_residual), self.weight_offset,
            self.requant_mult, self.requant_shift,
        )

def quantize_tensor_int8(w: torch.Tensor):
    w_np = w.detach().cpu().numpy().astype(np.float32)
    max_abs = max(float(np.abs(w_np).max()), 1e-8)
    scale = max_abs / 127.0
    q = np.round(w_np / scale).clip(-127, 127).astype(np.int8)
    return q, scale

def make_requant(in_scale: float, w_scale: float, out_scale: float):
    real_mult = (in_scale * w_scale) / max(out_scale, 1e-12)
    shift = 15
    mult = int(round(real_mult * (1 << shift)))
    while mult > 65535 and shift > 0:
        shift -= 1
        mult = int(round(real_mult * (1 << shift)))
    mult = max(0, min(65535, mult))
    return mult, shift

def _iter_blocks(model: nn.Module):
    for module in model.features.modules():
        if isinstance(module, nn.Conv2d):
            is_dw = module.groups == module.in_channels and module.in_channels == module.out_channels
            yield module, module.in_channels, module.out_channels, module.kernel_size[0], \
                module.stride[0], is_dw

def export(args):
    model = (build_mobilenetv3(pretrained=False) if args.model == "m1"
              else build_mobilenetv2(pretrained=False))
    state = torch.load(args.ckpt, map_location="cpu")
    model.load_state_dict(state)
    model.eval()

    layers: List[LayerDesc] = []
    weight_blob = bytearray()
    prev_out_scale = 1.0 / 127.0
    cur_h, cur_w = args.resolution, args.resolution

    for conv, in_ch, out_ch, kernel, stride, is_dw in _iter_blocks(model):
        q, w_scale = quantize_tensor_int8(conv.weight)
        out_scale = w_scale * prev_out_scale

        mult, shift = make_requant(prev_out_scale, w_scale, out_scale)

        offset = len(weight_blob)
        weight_blob += q.tobytes()

        ltype = LT_DEPTHWISE if is_dw else LT_POINTWISE if kernel == 1 else LT_STANDARD3x3
        act = ACT_HSWISH if args.model == "m1" else ACT_RELU6

        layers.append(LayerDesc(
            ltype=ltype, act=act, in_h=cur_h, in_w=cur_w, in_ch=in_ch, out_ch=out_ch,
            kernel=kernel, stride=stride, use_residual=(stride == 1 and in_ch == out_ch),
            weight_offset=offset, requant_mult=mult, requant_shift=shift,
        ))

        if stride == 2:
            cur_h //= 2
            cur_w //= 2
        prev_out_scale = out_scale

    fc_layer = model.classifier[-1]
    q_fc, fc_scale = quantize_tensor_int8(fc_layer.weight)
    fc_offset = len(weight_blob)
    weight_blob += q_fc.tobytes()
    mult, shift = make_requant(prev_out_scale, fc_scale, 1.0 / 127.0)
    layers.append(LayerDesc(
        ltype=LT_AVGPOOL, act=ACT_NONE, in_h=cur_h, in_w=cur_w,
        in_ch=fc_layer.in_features, out_ch=fc_layer.in_features,
        kernel=1, stride=1, use_residual=False, weight_offset=0,
        requant_mult=32768, requant_shift=15,
    ))
    layers.append(LayerDesc(
        ltype=LT_FC, act=ACT_NONE, in_h=1, in_w=1,
        in_ch=fc_layer.in_features, out_ch=fc_layer.out_features,
        kernel=1, stride=1, use_residual=False, weight_offset=fc_offset,
        requant_mult=mult, requant_shift=shift,
    ))

    with open(f"{args.out_prefix}_layers.bin", "wb") as f:
        for layer in layers:
            f.write(layer.pack())
    with open(f"{args.out_prefix}_weights.bin", "wb") as f:
        f.write(bytes(weight_blob))

    print(f"Exported {len(layers)} layers, {len(weight_blob)} bytes of INT8 weights "
          f"-> {args.out_prefix}_layers.bin / {args.out_prefix}_weights.bin")

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--ckpt", required=True)
    p.add_argument("--model", choices=["m1", "m2"], required=True)
    p.add_argument("--out_prefix", required=True)
    p.add_argument("--resolution", type=int, default=224)
    args = p.parse_args()
    export(args)
