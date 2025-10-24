from typing import Any
import numpy as np
from sklearn.svm import LinearSVC

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solves the SVM using scikit-learn's LinearSVC (primal form) and returns
        the same output format as the baseline CVXPY implementation.
        """
        X = np.array(problem["X"])
        y = np.array(problem["y"])
        C = float(problem["C"])

        # Fit a linear SVM with hinge loss (primal form)
        clf = LinearSVC(
            C=C,
            loss="hinge",
            dual=False,
            tol=1e-9,
            max_iter=10000,
            fit_intercept=True,
        )
        clf.fit(X, y)

        beta = clf.coef_.flatten()
        beta0 = clf.intercept_[0]

        # Compute predictions
        pred = X @ beta + beta0

        # Misclassification error
        missclass = np.mean((pred * y) < 0)

        # Compute objective value: 0.5 * ||beta||^2 + C * sum xi
        xi = np.maximum(0, 1 - y * pred)
        optimal_value = 0.5 * np.sum(beta ** 2) + C * np.sum(xi)

        return {
            "beta0": float(beta0),
            "beta": beta.tolist(),
            "optimal_value": float(optimal_value),
            "missclass_error": float(missclass),
        }