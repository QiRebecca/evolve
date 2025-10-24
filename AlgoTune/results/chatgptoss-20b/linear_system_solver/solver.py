from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the linear system Ax = b using NumPy's optimized solver.

        Args:
            problem (dict): A dictionary with keys "A" and "b".

        Returns:
            list: A list of numbers representing the solution vector x.
        """
        A = np.array(problem["A"])
        b = np.array(problem["b"])
        x = np.linalg.solve(A, b)
        return x.tolist()