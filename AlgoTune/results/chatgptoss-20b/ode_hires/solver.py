from typing import Any
import numpy as np
from scipy.integrate import solve_ivp

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the HIRES stiff ODE system using scipy's BDF solver.

        Parameters
        ----------
        problem : dict
            Dictionary containing:
                - t0 : float, initial time
                - t1 : float, final time
                - y0 : list[float], initial state of 8 species
                - constants : list[float], 12 rate constants

        Returns
        -------
        list[float]
            Final state vector at time t1.
        """
        t0 = problem["t0"]
        t1 = problem["t1"]
        y0 = np.array(problem["y0"], dtype=float)
        c = np.array(problem["constants"], dtype=float)

        # Unpack constants for readability
        c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12 = c

        def rhs(t, y):
            """
            Right-hand side of the HIRES ODE system.
            """
            y1, y2, y3, y4, y5, y6, y7, y8 = y

            dy1 = -c1 * y1 + c2 * y2 + c3 * y3 + c4
            dy2 = c1 * y1 - c5 * y2
            dy3 = -c6 * y3 + c2 * y4 + c7 * y5
            dy4 = c3 * y2 + c1 * y3 - c8 * y4
            dy5 = -c9 * y5 + c2 * y6 + c2 * y7
            dy6 = -c10 * y6 * y8 + c11 * y4 + c1 * y5 - c2 * y6 + c11 * y7
            dy7 = c10 * y6 * y8 - c12 * y7
            dy8 = -c10 * y6 * y8 + c12 * y7

            return np.array([dy1, dy2, dy3, dy4, dy5, dy6, dy7, dy8], dtype=float)

        # Use BDF method for stiff problems
        sol = solve_ivp(
            rhs,
            (t0, t1),
            y0,
            method="BDF",
            rtol=1e-6,
            atol=1e-9,
            vectorized=False,
            dense_output=False,
        )

        if not sol.success:
            raise RuntimeError(f"Solver failed: {sol.message}")

        return sol.y[:, -1].tolist()