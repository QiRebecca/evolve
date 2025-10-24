from typing import Any
import numpy as np
from scipy.integrate import solve_ivp

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """Solve the 1D Burgers' equation using method of lines with upwind
        advection and central diffusion, integrated with scipy's solve_ivp."""
        # Extract problem data
        t0 = float(problem["t0"])
        t1 = float(problem["t1"])
        y0 = np.array(problem["y0"], dtype=np.float64)
        params = problem["params"]
        nu = float(params["nu"])
        dx = float(params["dx"])
        # num_points = int(params["num_points"])  # not used directly
        # x_grid = problem["x_grid"]  # not used

        # Precompute constants
        dx2 = dx * dx

        def rhs(t, y):
            # y is shape (N,)
            # Upwind derivative
            y_left = np.concatenate([[0.0], y[:-1]])
            y_right = np.concatenate([y[1:], [0.0]])
            du_dx = np.where(y >= 0, (y - y_left) / dx, (y_right - y) / dx)

            # Diffusion term with Dirichlet zero boundaries
            y_padded = np.concatenate([[0.0], y, [0.0]])
            diff = nu * (y_padded[2:] - 2 * y_padded[1:-1] + y_padded[:-2]) / dx2

            return -y * du_dx + diff

        # Integrate using RK45
        sol = solve_ivp(
            rhs,
            (t0, t1),
            y0,
            method="RK45",
            rtol=1e-6,
            atol=1e-9,
            vectorized=False,
        )

        if not sol.success:
            raise RuntimeError(f"Solver failed: {sol.message}")

        return sol.y[:, -1].tolist()