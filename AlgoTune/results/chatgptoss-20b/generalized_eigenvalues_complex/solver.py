from typing import Any
import numpy as np
import scipy.linalg as la

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the generalized eigenvalue problem for the given matrices A and B.

        The problem is defined as: A · x = λ B · x.
        For better numerical stability, we first scale B, then solve the problem.

        The solution is a list of eigenvalues sorted in descending order, where the sorting order
        is defined as: first by the real part (descending), then by the imaginary part (descending).

        :param problem: Tuple (A, B) where A and B are n x n real matrices.
        :return: List of eigenvalues (complex numbers) sorted in descending order.
        """
        A, B = problem

        # Scale matrices for better numerical stability.
        scale_B = np.sqrt(np.linalg.norm(B))
        B_scaled = B / scale_B
        A_scaled = A / scale_B

        # Solve scaled problem using scipy.linalg.eigvals for speed.
        eigenvalues = la.eigvals(A_scaled, B_scaled)

        # Sort eigenvalues: descending order by real part, then by imaginary part.
        solution = sorted(eigenvalues, key=lambda x: (-x.real, -x.imag))

        return solution