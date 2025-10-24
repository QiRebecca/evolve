from typing import Any
import numpy as np
from scipy.integrate import solve_ivp

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the Robertson chemical kinetics ODE system.

        Parameters
        ----------
        problem : dict
            Dictionary containing:
                - t0 : float, initial time
                - t1 : float, final time
                - y0 : list[float], initial concentrations [y1, y2, y3]
                - k  : list[float], rate constants [k1, k2, k3]

        Returns
        -------
        list[float]
            Concentrations [y1, y2, y3] at time t1.
        """
        t0 = float(problem["t0"])
        t1 = float(problem["t1"])
        y0 = np.asarray(problem["y0"], dtype=float)
        k = np.asarray(problem["k"], dtype=float)

        def rhs(t, y):
            y1, y2, y3 = y
            k1, k2, k3 = k
            dy1 = -k1 * y1 + k3 * y2 * y3
            dy2 = k1 * y1 - k2 * y2 * y2 - k3 * y2 * y3
            dy3 = k2 * y2 * y2
            return [dy1, dy2, dy3]

        sol = solve_ivp(
            rhs,
            (t0, t1),
            y0,
            method="BDF",
            rtol=1e-6,
            atol=1e-9,
            vectorized=False,
        )

        if not sol.success:
            raise RuntimeError(f"Solver failed: {sol.message}")

        return sol.y[:, -1].tolist()