import numpy as np
from typing import Any
from sklearn.linear_model import LogisticRegression
import warnings

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve logistic regression with group-wise quadratic penalty using scikit-learn's
        LogisticRegression. The penalty λ * Σ_j w_j ||β_j||_2^2 is equivalent to an
        L2 penalty after scaling each feature in group j by sqrt(w_j). Here w_j = sqrt(p_j)
        where p_j is the number of features in group j.

        Parameters
        ----------
        problem : dict
            Dictionary containing:
                - "X": 2D list or array of shape (n, p+1) where first column is all ones.
                - "y": list of labels (0 or 1) of length n.
                - "gl": list of group labels for each of the p features (length p).
                - "lba": positive float λ.

        Returns
        -------
        dict
            Dictionary with keys:
                - "beta0": intercept (float)
                - "beta": list of coefficients (length p)
                - "optimal_value": objective value (float)
        """
        # Suppress convergence warnings for cleaner output
        warnings.filterwarnings("ignore", category=UserWarning)

        X = np.array(problem["X"], dtype=np.float64)
        y = np.array(problem["y"], dtype=np.float64)
        gl = np.array(problem["gl"], dtype=np.int64)
        lba = float(problem["lba"])

        # Number of features (excluding intercept column)
        p = X.shape[1] - 1

        # Compute group sizes
        unique_groups, inverse_indices, group_sizes = np.unique(gl, return_inverse=True, return_counts=True)

        # Compute scaling factors: sqrt(w_j) = (p_j)^(1/4)
        scaling_factors = np.power(group_sizes, 0.25)
        # Map each feature to its scaling factor
        feature_scaling = scaling_factors[inverse_indices]

        # Scale feature columns (excluding intercept)
        X_scaled = X[:, 1:] * feature_scaling

        # Fit logistic regression with L2 penalty
        # C = 1 / λ
        clf = LogisticRegression(
            penalty="l2",
            C=1.0 / lba,
            fit_intercept=True,
            solver="lbfgs",
            max_iter=10000,
            tol=1e-12,
            n_jobs=1,
        )
        clf.fit(X_scaled, y)

        beta = clf.coef_.flatten()
        beta0 = float(clf.intercept_[0])

        # Compute objective value on original data
        linear_pred = X @ np.concatenate([[beta0], beta])
        # Logistic loss
        log_loss = -np.sum(y * linear_pred) + np.sum(np.log1p(np.exp(linear_pred)))
        # Group penalty
        penalty = 0.0
        for idx, group in enumerate(unique_groups):
            # Indices of features in this group
            group_mask = (gl == group)
            beta_j = beta[group_mask]
            penalty += lba * np.sqrt(group_sizes[idx]) * np.sum(beta_j ** 2)

        optimal_value = log_loss + penalty

        return {
            "beta0": beta0,
            "beta": beta.tolist(),
            "optimal_value": float(optimal_value),
        }