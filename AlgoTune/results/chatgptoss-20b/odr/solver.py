from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """Fit weighted orthogonal distance regression via iterative weighted least squares."""
        x = np.asarray(problem["x"], dtype=np.float64)
        y = np.asarray(problem["y"], dtype=np.float64)
        sx = np.asarray(problem["sx"], dtype=np.float64)
        sy = np.asarray(problem["sy"], dtype=np.float64)

        # Initial estimate using weighted least squares with weights 1/sy^2
        w0 = 1.0 / sy**2
        S_w = np.sum(w0)
        S_wx = np.sum(w0 * x)
        S_wy = np.sum(w0 * y)
        S_wxx = np.sum(w0 * x * x)
        S_wxy = np.sum(w0 * x * y)
        denom = S_w * S_wxx - S_wx**2
        if denom == 0:
            a = 0.0
            b = 0.0
        else:
            a = (S_w * S_wxy - S_wx * S_wy) / denom
            b = (S_wy - a * S_wx) / S_w

        # Iterative refinement
        max_iter = 20
        tol = 1e-12
        for _ in range(max_iter):
            w = 1.0 / (sy**2 + a**2 * sx**2)
            S_w = np.sum(w)
            S_wx = np.sum(w * x)
            S_wy = np.sum(w * y)
            S_wxx = np.sum(w * x * x)
            S_wxy = np.sum(w * x * y)
            denom = S_w * S_wxx - S_wx**2
            if denom == 0:
                break
            a_new = (S_w * S_wxy - S_wx * S_wy) / denom
            b_new = (S_wy - a_new * S_wx) / S_w
            if np.abs(a_new - a) < tol and np.abs(b_new - b) < tol:
                a, b = a_new, b_new
                break
            a, b = a_new, b_new

        return {"beta": [float(a), float(b)]}