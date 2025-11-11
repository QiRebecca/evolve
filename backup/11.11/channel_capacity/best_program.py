import math
from typing import Any, Dict, List

import numpy as np
from scipy.special import xlogy


class Solver:
    """
    Channel–capacity solver for a discrete memory–less channel, using the
    Blahut–Arimoto algorithm (faster than general-purpose convex solvers).
    """

    def solve(self, problem: Dict[str, Any], **kwargs) -> Dict[str, Any]:
        """
        Parameters
        ----------
        problem : dict
            {"P": 2-D list/array of shape (m, n) with non-negative numbers whose
             columns sum to 1.  P[i, j] = P(Y=i | X=j)}
        kwargs : optional
            tol  : convergence tolerance on capacity (bits) – default 1e-10
            max_iters : iteration cap – default 10_000

        Returns
        -------
        dict
            {"x": optimal input distribution (length n, list of floats),
             "C": channel capacity in bits}
        """
        P = np.asarray(problem["P"], dtype=float)
        if P.ndim != 2:
            raise ValueError("P must be a 2-D array")
        m, n = P.shape

        # Normalise columns if they are not already (robustness)
        col_sums = P.sum(axis=0)
        if not np.allclose(col_sums, 1.0, atol=1e-12):
            P = P / col_sums  # broadcasting

        # Blahut–Arimoto parameters
        tol: float = kwargs.get("tol", 1e-10)
        max_iters: int = kwargs.get("max_iters", 10_000)
        ln2 = math.log(2.0)

        # Initial uniform input distribution
        x = np.full(n, 1.0 / n)

        prev_C = -np.inf
        for _ in range(max_iters):
            # Output distribution q_i = sum_j P_ij * x_j
            q = P @ x  # shape (m,)

            # Compute D_ij = log( P_ij / q_i ) where P_ij > 0, else 0
            with np.errstate(divide="ignore", invalid="ignore"):
                log_ratio = np.where(P > 0, np.log(P) - np.log(q)[:, None], 0.0)

            # Update x_j ∝ exp( Σ_i P_ij * log_ratio_ij )
            z = np.exp(np.sum(P * log_ratio, axis=0))
            x = z / z.sum()

            # Capacity in nats, then convert to bits
            C_nats = np.dot(x, np.sum(P * log_ratio, axis=0))
            C_bits = C_nats / ln2

            # Convergence check
            if abs(C_bits - prev_C) < tol:
                break
            prev_C = C_bits
        else:
            # If we exit via exhaustion of iterations, warn but continue
            pass

        return {"x": x.tolist(), "C": prev_C}