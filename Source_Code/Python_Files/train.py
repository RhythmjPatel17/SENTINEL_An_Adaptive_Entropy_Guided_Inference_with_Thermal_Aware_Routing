import argparse
import time

import torch
import torch.nn as nn
from torch.optim import Adam

from dataset import make_loaders
from models import build_mobilenetv2, build_mobilenetv3

def evaluate(model, loader, device):
    model.eval()
    correct, total, loss_sum = 0, 0, 0.0
    crit = nn.CrossEntropyLoss()
    with torch.no_grad():
        for x, y, _ in loader:
            x, y = x.to(device), y.to(device)
            logits = model(x)
            loss_sum += crit(logits, y).item() * x.size(0)
            pred = logits.argmax(dim=-1)
            correct += (pred == y).sum().item()
            total += x.size(0)
    return correct / max(total, 1), loss_sum / max(total, 1)

def train(args):
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    adaptive_res = (args.model == "m1")
    train_loader, val_loader, test_loader = make_loaders(
        args.data_root, batch_size=args.batch_size, resolution=args.resolution,
        adaptive_resolution=adaptive_res,
    )

    model = (build_mobilenetv3() if args.model == "m1" else build_mobilenetv2()).to(device)
    opt = Adam(model.parameters(), lr=args.lr)
    crit = nn.CrossEntropyLoss()

    best_val_acc = 0.0
    for epoch in range(1, args.epochs + 1):
        model.train()
        t0 = time.time()
        running_loss, running_correct, running_total = 0.0, 0, 0
        for x, y, _ in train_loader:
            x, y = x.to(device), y.to(device)
            opt.zero_grad()
            logits = model(x)
            loss = crit(logits, y)
            loss.backward()
            opt.step()

            running_loss += loss.item() * x.size(0)
            running_correct += (logits.argmax(dim=-1) == y).sum().item()
            running_total += x.size(0)

        train_acc = running_correct / max(running_total, 1)
        train_loss = running_loss / max(running_total, 1)
        val_acc, val_loss = evaluate(model, val_loader, device)

        print(f"[{args.model}] epoch {epoch:02d}/{args.epochs} "
              f"train_acc={train_acc:.3f} train_loss={train_loss:.3f} "
              f"val_acc={val_acc:.3f} val_loss={val_loss:.3f} "
              f"({time.time() - t0:.1f}s)")

        if val_acc > best_val_acc:
            best_val_acc = val_acc
            torch.save(model.state_dict(), args.out)

    test_acc, test_loss = evaluate(model, test_loader, device)
    print(f"[{args.model}] FINAL test_acc={test_acc:.3f} test_loss={test_loss:.3f}")
    print(f"Best checkpoint saved to {args.out}")

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--data_root", required=True)
    p.add_argument("--model", choices=["m1", "m2"], required=True)
    p.add_argument("--epochs", type=int, default=40)
    p.add_argument("--batch_size", type=int, default=64)
    p.add_argument("--lr", type=float, default=1e-4)
    p.add_argument("--resolution", type=int, default=224)
    p.add_argument("--out", type=str, default=None)
    args = p.parse_args()
    if args.out is None:
        args.out = f"{args.model}_wm811k.pt"
    train(args)
