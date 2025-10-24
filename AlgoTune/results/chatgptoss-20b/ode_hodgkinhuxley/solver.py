from typing import Any
import numpy as np
from scipy.integrate import solve_ivp

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the Hodgkin-Huxley model ODE from t0 to t1 and return the final state.
        """
        # Extract problem parameters
        t0 = problem["t0"]
        t1 = problem["t1"]
        y0 = np.array(problem["y0"], dtype=float)
        params = problem["params"]

        C_m = params["C_m"]
        g_Na = params["g_Na"]
        g_K = params["g_K"]
        g_L = params["g_L"]
        E_Na = params["E_Na"]
        E_K = params["E_K"]
        E_L = params["E_L"]
        I_app = params["I_app"]

        # Define rate functions
        def alpha_m(V):
            return 0.1 * (V + 40.0) / (1.0 - np.exp(-(V + 40.0) / 10.0))

        def beta_m(V):
            return 4.0 * np.exp(-(V + 65.0) / 18.0)

        def alpha_h(V):
            return 0.07 * np.exp(-(V + 65.0) / 20.0)

        def beta_h(V):
            return 1.0 / (1.0 + np.exp(-(V + 35.0) / 10.0))

        def alpha_n(V):
            return 0.01 * (V + 55.0) / (1.0 - np.exp(-(V + 55.0) / 10.0))

        def beta_n(V):
            return 0.125 * np.exp(-(V + 65.0) / 80.0)

        # ODE system
        def hh_ode(t, y):
            V, m, h, n = y
            dVdt = (I_app
                    - g_Na * m**3 * h * (V - E_Na)
                    - g_K * n**4 * (V - E_K)
                    - g_L * (V - E_L)) / C_m
            dmdt = alpha_m(V) * (1.0 - m) - beta_m(V) * m
            dhdt = alpha_h(V) * (1.0 - h) - beta_h(V) * h
            dndt = alpha_n(V) * (1.0 - n) - beta_n(V) * n
            return [dVdt, dmdt, dhdt, dndt]

        # Solve ODE
        sol = solve_ivp(
            hh_ode,
            (t0, t1),
            y0,
            method="RK45",
            rtol=1e-8,
            atol=1e-10,
            vectorized=False,
        )

        if not sol.success:
            raise RuntimeError(f"Solver failed: {sol.message}")

        return sol.y[:, -1].tolist()