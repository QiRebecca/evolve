from typing import Any
import numpy as np
import scipy.linalg as la

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the generalized eigenvalue problem A x = λ B x for real matrices A and B.
        Returns eigenvalues sorted by descending real part then imaginary part,
        and corresponding unit-norm eigenvectors.
        """
        A, B = problem

        # Scale matrices for numerical stability
        scale_B = np.sqrt(np.linalg.norm(B))
        if scale_B == 0:
            scale_B = 1.0
        A_scaled = A / scale_B
        B_scaled = B / scale_B

        # Compute generalized eigenvalues and right eigenvectors
        eigenvalues, eigenvectors = la.eig(A_scaled, B_scaled, left=False, right=True)

        # Normalize eigenvectors to unit Euclidean norm
        n = A.shape[0]
        for i in range(n):
            v = eigenvectors[:, i]
            norm = np.linalg.norm(v)
            if norm > 1e-15:
                eigenvectors[:, i] = v / norm

        # Pair eigenvalues with eigenvectors and sort
        pairs = list(zip(eigenvalues, eigenvectors.T))
        pairs.sort(key=lambda pair: (-pair[0].real, -pair[0].imag))
        sorted_eigenvalues, sorted_eigenvectors = zip(*pairs)

        # Convert to Python lists
        eigenvalues_list = [complex(val) for val in sorted_eigenvalues]
        eigenvectors_list = [list(vec) for vec in sorted_eigenvectors]

        return (eigenvalues_list, eigenvectors_list)