from typing import Any
import numpy as np
from scipy.linalg import lu

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        A = problem["matrix"]
        P, L, U = lu(A)
        return {"LU": {"P": P.tolist(), "L": L.tolist(), "U": U.tolist()}}