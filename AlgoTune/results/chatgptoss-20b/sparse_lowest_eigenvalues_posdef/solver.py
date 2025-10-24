from typing import Any
import numpy as np
from scipy.sparse.linalg import eigsh
import scipy.sparse

class Solver:
    def solve(self, problem: dict[str, Any], **kwargs) -> Any:
        """
        Compute the smallest k eigenvalues of a sparse positive semi-definite matrix.
        The matrix is expected to be provided in a format that supports .asformat('csr')
        or is already a scipy.sparse CSR matrix.
        """
        # Extract matrix and k
        mat = problem.get("matrix")
        if mat is None:
            raise ValueError("Problem must contain 'matrix' key.")
        # Ensure CSR format
        try:
            mat_csr = mat.asformat("csr")
        except AttributeError:
            # Assume it's already a scipy.sparse matrix
            mat_csr = scipy.sparse.csr_matrix(mat)
        k = int(problem.get("k", 0))
        if k <= 0:
            return []

        n = mat_csr.shape[0]

        # Dense path for tiny systems or k too close to n
        if k >= n or n < 2 * k + 1:
            vals = np.linalg.eigvalsh(mat_csr.toarray())
            return [float(v) for v in vals[:k]]

        # Sparse Lanczos without shift‑invert
        try:
            vals = eigsh(
                mat_csr,
                k=k,
                which="SM",  # smallest magnitude eigenvalues
                return_eigenvectors=False,
                maxiter=n * 200,
                ncv=min(n - 1, max(2 * k + 1, 20)),  # ensure k < ncv < n
            )
        except Exception:
            # Last‑resort dense fallback (rare)
            vals = np.linalg.eigvalsh(mat_csr.toarray())[:k]

        # Ensure real values and sort
        sorted_vals = np.sort(np.real(vals))
        return [float(v) for v in sorted_vals]