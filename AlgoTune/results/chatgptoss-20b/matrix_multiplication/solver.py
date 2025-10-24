from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the matrix product C = A · B efficiently.
        """
        A = np.array(problem["A"])
        B = np.array(problem["B"])
        return np.dot(A, B)