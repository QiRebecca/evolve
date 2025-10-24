from typing import Any
import numpy as np
from scipy.integrate import solve_ivp

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        t0 = problem["t0"]
        t1 = problem["t1"]
        y0 = np.array(problem["y0"], dtype=float)
        params = problem["params"]
        alpha = params["alpha"]
        beta = params["beta"]
        delta = params["delta"]
        gamma = params["gamma"]

        def lotka(t, y):
            x, y_pred = y
            dx = alpha * x - beta * x * y_pred
            dy = delta * x * y_pred - gamma * y_pred
            return [dx, dy]

        sol = solve_ivp(
            lotka,
            (t0, t1),
            y0,
            method="DOP853",
            rtol=1e-9,
            atol=1e-12,
            vectorized=False,
        )
        if not sol.success:
            raise RuntimeError(f"Solver failed: {sol.message}")
        final = sol.y[:, -1]
        final = np.maximum(final, 0.0)
        return final.tolist()