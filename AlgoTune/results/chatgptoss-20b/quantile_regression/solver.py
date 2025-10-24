from typing import Any
import numpy as np
from scipy.optimize import linprog

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Fit quantile regression using linear programming (scipy.optimize.linprog)
        and return parameters + in-sample predictions.

        Parameters
        ----------
        problem : dict
            Dictionary containing:
                - "X": array-like of shape (n_samples, n_features)
                - "y": array-like of shape (n_samples,)
                - "quantile": float in (0, 1)
                - "fit_intercept": bool

        Returns
        -------
        dict
            Dictionary with keys:
                - "coef": list of lists, shape (1, n_features)
                - "intercept": list of length 1
                - "predictions": list of predicted quantile values
        """
        X = np.asarray(problem["X"], dtype=float)
        y = np.asarray(problem["y"], dtype=float)
        tau = float(problem["quantile"])
        fit_intercept = bool(problem["fit_intercept"])

        n_samples, n_features = X.shape

        # Build design matrix
        if fit_intercept:
            X_design = np.hstack([np.ones((n_samples, 1)), X])
            p = n_features + 1
        else:
            X_design = X
            p = n_features

        # Objective coefficients: beta free, u_i, v_i
        c = np.zeros(p + 2 * n_samples)
        c[p: p + n_samples] = tau          # u_i coefficients
        c[p + n_samples:] = 1.0 - tau      # v_i coefficients

        # Inequality constraints A_ub x <= b_ub
        # First n rows: X_design * beta - v_i <= y_i
        A_ub = np.zeros((2 * n_samples, p + 2 * n_samples))
        b_ub = np.zeros(2 * n_samples)

        # Constraint 1: X_design * beta - v_i <= y_i
        A_ub[:n_samples, :p] = X_design
        A_ub[:n_samples, p + n_samples:p + 2 * n_samples] = -np.eye(n_samples)
        b_ub[:n_samples] = y

        # Constraint 2: -X_design * beta - u_i <= -y_i
        A_ub[n_samples:, :p] = -X_design
        A_ub[n_samples:, p:p + n_samples] = -np.eye(n_samples)
        b_ub[n_samples:] = -y

        # Bounds: beta free, u_i >= 0, v_i >= 0
        bounds = [(None, None)] * p + [(0, None)] * (2 * n_samples)

        # Solve linear program
        res = linprog(c, A_ub=A_ub, b_ub=b_ub, bounds=bounds, method="highs")

        if not res.success:
            # Fallback to scikit-learn if LP fails
            from sklearn.linear_model import QuantileRegressor
            model = QuantileRegressor(
                quantile=tau,
                alpha=0.0,
                fit_intercept=fit_intercept,
                solver="highs",
            )
            model.fit(X, y)
            beta = model.coef_
            intercept = model.intercept_
            predictions = model.predict(X)
        else:
            beta = res.x[:p]
            if fit_intercept:
                intercept = np.array([beta[0]])
                coef = beta[1:].reshape(1, -1)
            else:
                intercept = np.array([0.0])
                coef = beta.reshape(1, -1)
            predictions = X_design @ beta
            if not fit_intercept:
                predictions = predictions  # already without intercept

        return {
            "coef": coef.tolist(),
            "intercept": intercept.tolist(),
            "predictions": predictions.tolist(),
        }