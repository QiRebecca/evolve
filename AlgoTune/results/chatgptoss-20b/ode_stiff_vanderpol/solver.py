from typing import Any
import numpy as np
from scipy.integrate import solve_ivp

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the stiff Van der Pol oscillator using a stiff ODE solver.

        Parameters
        ----------
        problem : dict
            Dictionary containing:
                - 'mu' : float, stiffness parameter
                - 'y0' : list or array-like, initial state [x0, v0]
                - 't0' : float, initial time
                - 't1' : float, final time

        Returns
        -------
        list[float]
            Final state [x(t1), v(t1)].
        """
        # Extract parameters
        mu = float(problem["mu"])
        y0 = np.asarray(problem["y0"], dtype=float)
        t0 = float(problem["t0"])
        t1 = float(problem["t1"])

        # Define the system of first-order ODEs
        def f(t, y):
            x, v = y
            return [v, mu * (1 - x**2) * v - x]

        # Solve using a stiff solver (Radau)
        sol = solve_ivp(
            f,
            (t0, t1),
            y0,
            method="Radau",
            rtol=1e-6,
            atol=1e-9,
            t_eval=[t1],
        )

        if not sol.success:
            raise RuntimeError(f"Solver failed: {sol.message}")

        # Return final state as a list
        return sol.y[:, -1].tolist()