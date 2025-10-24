from typing import Any
import numpy as np
import cvxpy as cp

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solves a robust linear program with ellipsoidal uncertainty using CVXPY.

        Parameters
        ----------
        problem : dict
            Dictionary containing problem data:
                - "c": list or array of shape (n,)
                - "b": list or array of shape (m,)
                - "P": list of m matrices, each of shape (n, n)
                - "q": list or array of shape (m, n)

        Returns
        -------
        dict
            Dictionary with keys:
                - "objective_value": float, optimal objective value
                - "x": list of floats, optimal solution vector
        """
        # Convert inputs to numpy arrays
        c = np.array(problem["c"], dtype=float)
        b = np.array(problem["b"], dtype=float)
        P = np.array(problem["P"], dtype=float)
        q = np.array(problem["q"], dtype=float)

        m = P.shape[0]
        n = c.shape[0]

        # Decision variable
        x = cp.Variable(n)

        # Build SOC constraints
        constraints = []
        for i in range(m):
            # Compute P[i].T @ x
            PiT_x = P[i].T @ x
            # SOC: ||PiT_x||_2 <= b[i] - q[i].T @ x
            constraints.append(cp.SOC(b[i] - q[i].T @ x, PiT_x))

        # Objective
        objective = cp.Minimize(c.T @ x)

        # Problem definition
        prob = cp.Problem(objective, constraints)

        try:
            # Solve using ECOS solver (supports SOCP)
            prob.solve(solver=cp.ECOS, verbose=False)

            # Check status
            if prob.status not in ["optimal", "optimal_inaccurate"]:
                # Return inf and NaNs if not optimal
                return {"objective_value": float("inf"), "x": [float("nan")] * n}

            return {"objective_value": prob.value, "x": x.value.tolist()}
        except Exception:
            # In case of any error, return inf and NaNs
            return {"objective_value": float("inf"), "x": [float("nan")] * n}