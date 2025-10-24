from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the Euclidean projection of a point y onto the probability simplex.
        This implementation follows the algorithm described in
        https://arxiv.org/pdf/1309.1541 and runs in O(n log n) time.
        """
        y = np.array(problem.get("y", []), dtype=float)
        # Ensure y is a 1-D array
        y = y.flatten()
        n = y.size
        if n == 0:
            return {"solution": np.array([])}

        # Sort y in descending order
        sorted_y = np.sort(y)[::-1]

        # Compute cumulative sum of sorted_y minus 1
        cumsum_y = np.cumsum(sorted_y) - 1.0

        # Find the largest index rho such that sorted_y > cumsum_y / (rho+1)
        # Using vectorized operations for speed
        div = cumsum_y / (np.arange(1, n + 1))
        mask = sorted_y > div
        # mask is a boolean array; find last True index
        rho = np.where(mask)[0][-1]

        theta = cumsum_y[rho] / (rho + 1.0)

        # Project onto the simplex
        x = np.maximum(y - theta, 0.0)

        return {"solution": x}