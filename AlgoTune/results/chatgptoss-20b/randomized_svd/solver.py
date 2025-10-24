from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute an approximate randomized SVD of matrix A.

        Parameters
        ----------
        problem : dict
            Dictionary containing:
                - "matrix": numpy array of shape (n, m)
                - "n_components": int, number of singular values/vectors to compute
                - "matrix_type": str, used to determine number of power iterations

        Returns
        -------
        dict
            Dictionary with keys:
                - "U": (n, k) array of left singular vectors
                - "S": (k,) array of singular values
                - "V": (m, k) array of right singular vectors
        """
        A = problem["matrix"]
        n_components = problem["n_components"]
        matrix_type = problem.get("matrix_type", "")

        # Determine number of power iterations
        n_iter = 10 if matrix_type == "ill_conditioned" else 5

        n, m = A.shape
        k = min(n_components, min(n, m))

        # Oversampling parameter
        p = 5
        l = min(k + p, min(n, m))

        rng = np.random.default_rng(42)
        # Random Gaussian test matrix
        Omega = rng.standard_normal((m, l))

        # Sample the range of A
        Y = A @ Omega

        # Power iterations to improve accuracy
        for _ in range(n_iter):
            Y = A @ (A.T @ Y)

        # Orthonormalize Y
        Q, _ = np.linalg.qr(Y, mode="reduced")

        # Project A onto the subspace
        B = Q.T @ A

        # Compute SVD of the small matrix B
        U_small, s, Vt_small = np.linalg.svd(B, full_matrices=False)

        # Form the approximate left singular vectors
        U = Q @ U_small[:, :k]
        V = Vt_small.T[:, :k]
        s = s[:k]

        return {"U": U, "S": s, "V": V}