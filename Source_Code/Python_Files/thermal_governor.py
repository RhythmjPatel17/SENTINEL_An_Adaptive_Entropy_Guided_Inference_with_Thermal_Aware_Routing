import glob
import os

class ThermalGovernor:
    def __init__(self, tau_base: float = 0.82, tau_min: float = 0.62,
                 alpha: float = 0.008, t_crit: float = 75.0):
        self.tau_base = tau_base
        self.tau_min = tau_min
        self.alpha = alpha
        self.t_crit = t_crit

    def threshold(self, t_junction_c: float) -> float:
        tau = self.tau_base - self.alpha * (t_junction_c - self.t_crit)
        return max(self.tau_min, tau)

    @staticmethod
    def read_jetson_temperature(zone_hint: str = "GPU") -> float:
        candidates = sorted(glob.glob("/sys/class/thermal/thermal_zone*"))
        best = None
        for zone in candidates:
            try:
                with open(os.path.join(zone, "type")) as f:
                    ztype = f.read().strip()
                with open(os.path.join(zone, "temp")) as f:
                    milli_c = int(f.read().strip())
                if zone_hint.lower() in ztype.lower():
                    return milli_c / 1000.0
                if best is None:
                    best = milli_c / 1000.0
            except (FileNotFoundError, PermissionError, ValueError):
                continue
        if best is None:
            raise RuntimeError("No readable thermal zone found on this platform.")
        return best

if __name__ == "__main__":
    gov = ThermalGovernor()
    for t in [55, 60, 65, 70, 75, 80, 85]:
        print(f"Tj={t:>3}C  tau={gov.threshold(t):.3f}")
