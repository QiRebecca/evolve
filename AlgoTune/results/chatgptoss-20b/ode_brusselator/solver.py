from typing import Any
import numpy as np
from scipy.integrate import solve_ivp

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """Solve the Brusselator ODE and return the state at final time."""
        t0 = problem["t0"]
        t1 = problem["t1"]
        y0 = np.array(problem["y0"], dtype=float)
        A = problem["params"]["A"]
        B = problem["params"]["B"]

        def rhs(t, y):
            X, Y = y
            dX = A + X**2 * Y - (B + 1) * X
            dY = B * X - X**2 * Y
            return [dX, dY]

        sol = solve_ivp(
            rhs,
            (t0, t1),
            y0,
            method="DOP853",
            rtol=1e-8,
            atol=1e-10,
            t_eval=[t1],
        )

        if not sol.success:
            raise RuntimeError(f"Solver failed: {sol.message}")

        return sol.y[:, -1]