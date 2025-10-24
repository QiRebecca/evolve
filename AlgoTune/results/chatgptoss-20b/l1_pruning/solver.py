from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the L1 proximal operator / projection onto the L1 ball.

        The algorithm follows the efficient O(n log n) method described in
        https://doi.org/10.1109/CVPR.2018.00890. It handles the special
        cases where the radius k is larger than the L1 norm of v (in which
        case the solution is v itself) or where k is non‑positive (solution
        is the zero vector).
        """
        v = np.array(problem.get("v"), dtype=float)
        k = problem.get("k")

        # Ensure v is a 1‑D array
        v = v.flatten()
        u = np.abs(v)

        # If k is non‑positive, return zero vector
        if k <= 0:
            return {"solution": np.zeros_like(v).tolist()}

        # If k is larger than the L1 norm of v, the projection is v itself
        if k >= u.sum():
            return {"solution": v.tolist()}

        # Sort u in descending order
        u_sorted = np.sort(u)[::-1]
        cumsum = np.cumsum(u_sorted)

        # Compute thresholds: (cumsum - k) / (1..n)
        n = len(u)
        thresholds = (cumsum - k) / np.arange(1, n + 1)

        # Find the largest index where u_sorted > threshold
        mask = u_sorted > thresholds
        if not np.any(mask):
            # This should not happen for k < sum(u), but guard anyway
            theta = 0.0
        else:
            rho = np.where(mask)[0][-1]
            theta = (cumsum[rho] - k) / (rho + 1)

        # Compute the projected vector
        w = np.maximum(u - theta, 0.0)
        w = w * np.sign(v)

        return {"solution": w.tolist()}