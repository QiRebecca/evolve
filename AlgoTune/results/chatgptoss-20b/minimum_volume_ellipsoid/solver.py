from typing import Any
import numpy as np
import cvxpy as cp
import logging

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solves the minimum volume covering ellipsoid problem using CVXPY.

        Parameters
        ----------
        problem : dict
            Dictionary containing the key "points" with an array-like of shape (n, d).

        Returns
        -------
        dict
            Dictionary with keys:
                - "objective_value": float, optimal objective value.
                - "ellipsoid": dict with keys "X" (d x d array) and "Y" (d array).
        """
        points = np.array(problem["points"])
        if points.ndim != 2:
            raise ValueError("Points must be a 2D array.")
        n, d = points.shape

        # Variables
        X = cp.Variable((d, d), symmetric=True)
        Y = cp.Variable(d)

        # Constraints: SOC for each point
        constraints = [cp.SOC(1, X @ points[i] + Y) for i in range(n)]

        # Objective: minimize -log_det(X)
        objective = cp.Minimize(-cp.log_det(X))

        prob = cp.Problem(objective, constraints)

        try:
            prob.solve(solver=cp.CLARABEL, verbose=False)
        except Exception as e:
            logging.error(f"Solver failed: {e}")
            return {
                "objective_value": float("inf"),
                "ellipsoid": {"X": np.full((d, d), np.nan), "Y": np.full(d, np.nan)},
            }

        if prob.status not in ["optimal", "optimal_inaccurate"]:
            logging.warning(f"Solver status: {prob.status}")
            return {
                "objective_value": float("inf"),
                "ellipsoid": {"X": np.full((d, d), np.nan), "Y": np.full(d, np.nan)},
            }

        X_val = X.value
        Y_val = Y.value

        if X_val is None or Y_val is None:
            logging.error("Solver returned None for variables.")
            return {
                "objective_value": float("inf"),
                "ellipsoid": {"X": np.full((d, d), np.nan), "Y": np.full(d, np.nan)},
            }

        return {
            "objective_value": prob.value,
            "ellipsoid": {"X": X_val, "Y": Y_val},
        }
