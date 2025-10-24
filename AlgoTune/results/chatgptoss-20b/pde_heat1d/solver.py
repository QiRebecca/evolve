from typing import Any
import numpy as np
from scipy.integrate import solve_ivp

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the 1D heat equation using the method of lines and a stiff ODE solver.
        """
        # Extract problem parameters
        t0 = float(problem["t0"])
        t1 = float(problem["t1"])
        y0 = np.array(problem["y0"], dtype=float)
        params = problem["params"]
        alpha = float(params["alpha"])
        dx = float(params["dx"])
        # num_points is not needed directly; y0 length gives it
        factor = alpha / (dx * dx)

        n = y0.size

        def rhs(t, y):
            # Compute second spatial derivative with Dirichlet BCs (u=0 at boundaries)
            lap = np.empty_like(y)
            if n == 1:
                lap[0] = -2.0 * y[0]
            else:
                lap[0] = y[1] - 2.0 * y[0]
                lap[-1] = -2.0 * y[-1] + y[-2]
                lap[1:-1] = y[2:] - 2.0 * y[1:-1] + y[:-2]
            return factor * lap

        # Use a stiff solver (BDF) for efficiency on fine grids
        sol = solve_ivp(
            rhs,
            (t0, t1),
            y0,
            method="BDF",
            rtol=1e-8,
            atol=1e-10,
            vectorized=False,
        )

        if not sol.success:
            raise RuntimeError(f"Solver failed: {sol.message}")

        return sol.y[:, -1].tolist()