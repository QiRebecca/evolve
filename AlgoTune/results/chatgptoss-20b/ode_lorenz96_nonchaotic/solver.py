from typing import Any
import numpy as np
from scipy.integrate import solve_ivp

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the Lorenz 96 system for the given problem dictionary.

        Parameters
        ----------
        problem : dict
            Dictionary containing:
                - 'F' : float, forcing term
                - 't0' : float, initial time
                - 't1' : float, final time
                - 'y0' : list[float] or np.ndarray, initial state

        Returns
        -------
        list[float]
            State vector at time t1.
        """
        # Extract parameters
        F = float(problem["F"])
        t0 = float(problem["t0"])
        t1 = float(problem["t1"])
        y0 = np.asarray(problem["y0"], dtype=float)

        N = y0.size

        def lorenz96(t, y):
            # Vectorized implementation using numpy roll for cyclic indices
            return (np.roll(y, -1) - np.roll(y, 2)) * np.roll(y, 1) - y + F

        # Solve ODE
        sol = solve_ivp(
            lorenz96,
            (t0, t1),
            y0,
            method="RK45",
            rtol=1e-9,
            atol=1e-12,
            t_eval=[t1],
            vectorized=True,
        )

        if not sol.success:
            raise RuntimeError(f"Solver failed: {sol.message}")

        return sol.y[:, -1].tolist()