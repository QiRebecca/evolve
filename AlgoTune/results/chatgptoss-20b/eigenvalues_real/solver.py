from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute eigenvalues of a symmetric matrix efficiently.
        """
        # Compute eigenvalues only using eigvalsh for speed.
        eigvals = np.linalg.eigvalsh(problem)
        # Sort in descending order.
        eigvals_desc = np.sort(eigvals)[::-1]
        return eigvals_desc.tolist()