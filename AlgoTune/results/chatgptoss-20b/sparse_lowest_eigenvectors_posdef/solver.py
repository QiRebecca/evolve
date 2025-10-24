from typing import Any
import numpy as np
from scipy.sparse.linalg import eigsh
from scipy import sparse

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the k smallest eigenvalues of a sparse positive semi-definite matrix.
        The input `problem` is expected to be a dictionary with keys:
            - "matrix": a scipy sparse matrix (CSR or convertible to CSR)
            - "k": integer number of smallest eigenvalues to return
        Returns a list of floats containing the k smallest eigenvalues in ascending order.
        """
        mat = problem["matrix"]
        # Ensure matrix is in CSR format for efficient operations
        if not sparse.isspmatrix_csr(mat):
            mat = mat.tocsr()
        k = int(problem["k"])
        n = mat.shape[0]

        # Dense path for tiny systems or when k is close to n
        if k >= n or n < 2 * k + 1:
            vals = np.linalg.eigvalsh(mat.toarray())
            return [float(v) for v in vals[:k]]

        # Sparse Lanczos method to compute smallest magnitude eigenvalues
        try:
            vals = eigsh(
                mat,
                k=k,
                which="SM",  # smallest magnitude eigenvalues
                return_eigenvectors=False,
                maxiter=n * 200,
                ncv=min(n - 1, max(2 * k + 1, 20)),  # ensure k < ncv < n
            )
        except Exception:
            # Fallback to dense computation if sparse method fails
            vals = np.linalg.eigvalsh(mat.toarray())[:k]

        # Ensure real values and sorted order
        return [float(v) for v in np.sort(np.real(vals))]