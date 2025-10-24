from typing import Any
import numpy as np
from scipy.integrate import solve_ivp

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the FitzHugh-Nagumo ODE system and return the state at final time.

        Parameters
        ----------
        problem : dict
            Dictionary containing:
                - t0 : float, initial time
                - t1 : float, final time
                - y0 : list[float], initial state [v0, w0]
                - params : dict, containing 'a', 'b', 'c', 'I'

        Returns
        -------
        list[float]
            Final state [v, w] at time t1.
        """
        # Extract problem data
        t0 = problem["t0"]
        t1 = problem["t1"]
        y0 = np.array(problem["y0"], dtype=float)
        params = problem["params"]
        a = params["a"]
        b = params["b"]
        c = params["c"]
        I = params["I"]

        # Define the ODE system
        def f(t, y):
            v, w = y
            dv = v - v**3 / 3.0 - w + I
            dw = a * (b * v - c * w)
            return [dv, dw]

        # Solve using scipy's solve_ivp with default tolerances
        sol = solve_ivp(
            f,
            (t0, t1),
            y0,
            method="RK45",
            rtol=1e-6,
            atol=1e-9,
            vectorized=False,
        )

        if not sol.success:
            raise RuntimeError(f"Solver failed: {sol.message}")

        # Return final state as a list of floats
        return sol.y[:, -1].tolist()