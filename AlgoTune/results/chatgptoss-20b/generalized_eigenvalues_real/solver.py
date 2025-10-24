from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the generalized eigenvalue problem A x = λ B x for symmetric A and SPD B.
        Returns a list of eigenvalues sorted in descending order.
        """
        A, B = problem

        # Cholesky decomposition of B
        L = np.linalg.cholesky(B)

        # Compute the inverse of L
        Linv = np.linalg.inv(L)

        # Transform to standard eigenvalue problem
        Atilde = Linv @ A @ Linv.T

        # Compute eigenvalues (ascending order)
        eigs = np.linalg.eigh(Atilde)[0]

        # Return eigenvalues in descending order as a list of floats
        return eigs[::-1].tolist()