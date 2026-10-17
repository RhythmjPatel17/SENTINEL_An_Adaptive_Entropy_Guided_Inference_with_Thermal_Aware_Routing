import torch
import torch.nn as nn
import torchvision.models as tvm

WM811K_CLASSES = [
    "center", "donut", "edge-loc", "edge-ring",
    "loc", "near-full", "random", "scratch",
]
NUM_CLASSES = len(WM811K_CLASSES)

def build_mobilenetv3(num_classes: int = NUM_CLASSES, pretrained: bool = True) -> nn.Module:
    weights = tvm.MobileNet_V3_Small_Weights.DEFAULT if pretrained else None
    model = tvm.mobilenet_v3_small(weights=weights)
    in_features = model.classifier[-1].in_features
    model.classifier[-1] = nn.Linear(in_features, num_classes)
    return model

def build_mobilenetv2(num_classes: int = NUM_CLASSES, pretrained: bool = True) -> nn.Module:
    weights = tvm.MobileNet_V2_Weights.DEFAULT if pretrained else None
    model = tvm.mobilenet_v2(weights=weights)
    in_features = model.classifier[-1].in_features
    model.classifier[-1] = nn.Linear(in_features, num_classes)
    return model

@torch.no_grad()
def softmax_probs(model: nn.Module, x: torch.Tensor) -> torch.Tensor:
    logits = model(x)
    return torch.softmax(logits, dim=-1)

if __name__ == "__main__":
    m1 = build_mobilenetv3(pretrained=False)
    m2 = build_mobilenetv2(pretrained=False)
    dummy = torch.randn(1, 3, 224, 224)
    print("M1 (MobileNetV3-Small) out:", m1(dummy).shape)
    print("M2 (MobileNetV2) out:", m2(dummy).shape)
