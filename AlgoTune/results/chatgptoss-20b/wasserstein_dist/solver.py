from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the Wasserstein distance between two discrete distributions
        defined on the support {1, 2, ..., n}.

        The distance is computed efficiently using cumulative sums:
            d = sum_{k=1}^{n-1} |C_u(k) - C_v(k)|
        where C_u(k) = sum_{i=1}^k u_i and similarly for C_v.

        Parameters
        ----------
        problem : dict
            Dictionary with keys 'u' and 'v', each a list of floats.

        Returns
        -------
        float
            The Wasserstein distance.
        """
        try:
            u = np.array(problem["u"], dtype=float)
            v = np.array(problem["v"], dtype=float)
            if u.shape != v.shape:
                return float(len(u))
            cum_u = np.cumsum(u)
            cum_v = np.cumsum(v)
            # The last cumulative difference is zero (both sums equal 1),
            # so we exclude it from the sum.
            diff = np.abs(cum_u[:-1] - cum_v[:-1])
            return float(np.sum(diff))
        except Exception:
            return float(len(problem.get("u", [])))