from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute eigenvalues and eigenvectors of a real square matrix,
        sort the eigenpairs by descending real part then imaginary part,
        normalize eigenvectors to unit Euclidean norm, and return the
        list of eigenvectors in the sorted order.
        """
        A = np.asarray(problem, dtype=float)
        eigenvalues, eigenvectors = np.linalg.eig(A)

        # Sort eigenpairs: descending by real part, then imaginary part
        order = np.lexsort((-eigenvalues.imag, -eigenvalues.real))
        eigenvalues = eigenvalues[order]
        eigenvectors = eigenvectors[:, order]

        # Normalize eigenvectors (columns)
        norms = np.linalg.norm(eigenvectors, axis=0)
        # Avoid division by zero for zero-norm columns
        norms[norms < 1e-12] = 1.0
        eigenvectors = eigenvectors / norms

        # Convert to list of lists of complex numbers
        result = [eigenvectors[:, i].tolist() for i in range(eigenvectors.shape[1])]
        return result