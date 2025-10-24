from typing import Any
import numpy as np

class Solver:
    def solve(self, problem: dict[str, Any], **kwargs) -> Any:
        """
        Solve the water-filling problem analytically.

        Parameters
        ----------
        problem : dict
            Dictionary containing:
                - "alpha": list of positive floats
                - "P_total": positive float

        Returns
        -------
        dict
            Dictionary with keys:
                - "x": list of optimal power allocations
                - "Capacity": maximized total capacity
        """
        # Extract and validate inputs
        alpha = np.asarray(problem.get("alpha", []), dtype=float)
        P_total = float(problem.get("P_total", 0.0))
        n = alpha.size

        # Check for invalid data
        if n == 0 or P_total <= 0 or not np.all(alpha > 0) or not np.isfinite(P_total) or not np.all(np.isfinite(alpha)):
            return {"x": [float("nan")] * n, "Capacity": float("nan")}

        # Sort alpha ascending
        idx = np.argsort(alpha)
        alpha_sorted = alpha[idx]
        cum_alpha = np.cumsum(alpha_sorted)

        # Find water level λ
        lambda_val = None
        for k in range(1, n + 1):
            lambda_k = (P_total + cum_alpha[k - 1]) / k
            if lambda_k > alpha_sorted[k - 1] and (k == n or lambda_k <= alpha_sorted[k]):
                lambda_val = lambda_k
                break

        if lambda_val is None:
            # Fallback: use mean of alpha plus P_total/n
            lambda_val = (P_total + cum_alpha[-1]) / n

        # Compute allocations in sorted order
        x_sorted = np.maximum(0.0, lambda_val - alpha_sorted)

        # Reorder to original order
        x = np.empty_like(x_sorted)
        x[idx] = x_sorted

        # Compute capacity
        capacity = float(np.sum(np.log(alpha + x)))

        return {"x": x.tolist(), "Capacity": capacity}