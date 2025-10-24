from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute eigenvalues and eigenvectors of a real symmetric matrix.
        Returns eigenvalues sorted in descending order and corresponding eigenvectors
        as a list of lists (each inner list is an eigenvector).
        """
        # Use numpy's eigh which is efficient for symmetric matrices.
        eigenvalues, eigenvectors = np.linalg.eigh(problem)
        # Reverse to descending order
        eigenvalues = eigenvalues[::-1]
        eigenvectors = eigenvectors[:, ::-1]
        # Convert to lists
        eigenvalues_list = eigenvalues.tolist()
        eigenvectors_list = [eigenvectors[:, i].tolist() for i in range(eigenvectors.shape[1])]
        return (eigenvalues_list, eigenvectors_list)