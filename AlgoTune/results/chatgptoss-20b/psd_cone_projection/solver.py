from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the projection of a symmetric matrix onto the cone of
        positive semidefinite matrices using eigen-decomposition.
        """
        A = np.array(problem["A"], dtype=float)
        # Use eigh for symmetric matrices (faster and more stable)
        eigvals, eigvecs = np.linalg.eigh(A)
        # Set negative eigenvalues to zero
        eigvals = np.maximum(eigvals, 0)
        # Reconstruct the projected matrix
        X = eigvecs @ np.diag(eigvals) @ eigvecs.T
        return {"X": X}