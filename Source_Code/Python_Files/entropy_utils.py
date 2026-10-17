import numpy as np

EPS = 1e-12

def shannon_entropy(p: np.ndarray) -> float:
    p = np.clip(p, EPS, 1.0)
    return float(-np.sum(p * np.log(p)))

def normalized_confidence(p: np.ndarray) -> float:
    c_classes = p.shape[-1]
    h = shannon_entropy(p)
    return float(1.0 - h / np.log(c_classes))

def batch_confidence(P: np.ndarray) -> np.ndarray:
    P = np.clip(P, EPS, 1.0)
    C = P.shape[-1]
    H = -np.sum(P * np.log(P), axis=-1)
    return 1.0 - H / np.log(C)
