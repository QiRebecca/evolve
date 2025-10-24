from typing import Any
import numpy as np
import scipy.sparse.linalg as sparse

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the eigenvalue problem for the given square sparse matrix.
        The solution returned is a list of the eigenvectors with the largest `k` eigenvalues sorted in descending order by their modulus.
        """
        A = problem["matrix"]
        k = problem["k"]
        N = A.shape[0]
        # Deterministic starting vector
        v0 = np.ones(N, dtype=A.dtype)

        # Compute eigenvalues and eigenvectors using scipy.sparse.linalg.eigs
        eigenvalues, eigenvectors = sparse.eigs(
            A,
            k=k,
            v0=v0,
            maxiter=N * 200,
            ncv=max(2 * k + 1, 20),
        )

        # Pair eigenvalues with corresponding eigenvectors
        pairs = list(zip(eigenvalues, eigenvectors.T))
        # Sort by descending order of eigenvalue modulus
        pairs.sort(key=lambda pair: -np.abs(pair[0]))

        # Extract sorted eigenvectors
        solution = [pair[1] for pair in pairs]
        return solution