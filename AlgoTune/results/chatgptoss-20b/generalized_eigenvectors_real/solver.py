from typing import Any
import numpy as np
from scipy.linalg import eigh

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the generalized eigenvalue problem A x = λ B x using scipy.linalg.eigh
        which directly handles the generalized case. The returned eigenvalues are
        sorted in descending order and the eigenvectors are B-orthonormal.
        """
        A, B = problem

        # Compute eigenvalues and eigenvectors for the generalized problem.
        eigenvalues, eigenvectors = eigh(A, B, eigvals_only=False)

        # Reverse to descending order.
        eigenvalues = eigenvalues[::-1]
        eigenvectors = eigenvectors[:, ::-1]

        # Convert to lists for the expected output format.
        eigenvalues_list = eigenvalues.tolist()
        eigenvectors_list = [eigenvectors[:, i].tolist() for i in range(eigenvectors.shape[1])]

        return (eigenvalues_list, eigenvectors_list)