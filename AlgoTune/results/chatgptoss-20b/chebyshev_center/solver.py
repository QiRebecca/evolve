from typing import Any
import numpy as np
from scipy.optimize import linprog

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the Chebyshev center problem using SciPy's linprog for speed.
        """
        a = np.array(problem["a"], dtype=float)
        b = np.array(problem["b"], dtype=float)
        m, n = a.shape

        # Norms of the rows of a
        norms = np.linalg.norm(a, axis=1)

        # Build the inequality matrix A_ub and vector b_ub
        # Variables: [x1, ..., xn, r]
        A_ub = np.zeros((m + 1, n + 1))
        A_ub[:m, :n] = a
        A_ub[:m, n] = norms
        # r >= 0 constraint: -r <= 0
        A_ub[m, n] = -1
        b_ub = np.concatenate([b, [0]])

        # Objective: maximize r -> minimize -r
        c = np.zeros(n + 1)
        c[n] = -1

        # Bounds: x free, r >= 0
        bounds = [(None, None)] * n + [(0, None)]

        res = linprog(c, A_ub=A_ub, b_ub=b_ub, bounds=bounds, method="highs")

        if not res.success:
            raise RuntimeError(f"Linear program failed: {res.message}")

        x_opt = res.x[:n]
        return {"solution": x_opt.tolist()}