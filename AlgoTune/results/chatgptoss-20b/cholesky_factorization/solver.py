from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the Cholesky factorization of a symmetric positive definite matrix A.
        """
        A = problem["matrix"]
        L = np.linalg.cholesky(A)
        return {"Cholesky": {"L": L}}