from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        A = problem.get("A")
        B = problem.get("B")
        if A is None or B is None:
            return {}
        A = np.array(A, dtype=float)
        B = np.array(B, dtype=float)
        if A.shape != B.shape:
            return {}
        M = B @ A.T
        U, _, Vt = np.linalg.svd(M, full_matrices=False)
        G = U @ Vt
        return {"solution": G.tolist()}