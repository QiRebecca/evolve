from typing import Any
import numpy as np
from scipy.integrate import solve_ivp

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the SEIRS epidemic model ODE from t0 to t1.

        Parameters
        ----------
        problem : dict
            Dictionary containing:
                - t0 : float, initial time
                - t1 : float, final time
                - y0 : list[float], initial state [S, E, I, R]
                - params : dict, model parameters
                    - beta : float
                    - sigma : float
                    - gamma : float
                    - omega : float

        Returns
        -------
        list[float]
            Final state [S, E, I, R] at time t1.
        """
        # Extract problem data
        t0 = problem["t0"]
        t1 = problem["t1"]
        y0 = np.array(problem["y0"], dtype=float)
        params = problem["params"]
        beta = params["beta"]
        sigma = params["sigma"]
        gamma = params["gamma"]
        omega = params["omega"]

        # Define the ODE system
        def seirs(t, y):
            S, E, I, R = y
            dS = -beta * S * I + omega * R
            dE = beta * S * I - sigma * E
            dI = sigma * E - gamma * I
            dR = gamma * I - omega * R
            return [dS, dE, dI, dR]

        # Solve the ODE
        sol = solve_ivp(
            seirs,
            t_span=(t0, t1),
            y0=y0,
            method="RK45",
            rtol=1e-8,
            atol=1e-10,
            vectorized=False,
            **kwargs
        )

        if not sol.success:
            raise RuntimeError(f"Solver failed: {sol.message}")

        # Return final state as list
        return sol.y[:, -1].tolist()