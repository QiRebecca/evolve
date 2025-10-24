from typing import Any
import numpy as np
from sklearn.cluster import KMeans

class Solver:
    def solve(self, problem: dict[str, Any], **kwargs) -> Any:
        """
        Perform spectral clustering on the provided similarity matrix.

        Parameters
        ----------
        problem : dict
            Must contain keys:
                - "similarity_matrix": 2D numpy array (square)
                - "n_clusters": int > 0

        Returns
        -------
        dict
            {"labels": numpy array of cluster assignments}
        """
        # Extract inputs
        similarity_matrix = problem.get("similarity_matrix")
        n_clusters = problem.get("n_clusters")

        # Basic validation
        if not isinstance(similarity_matrix, np.ndarray):
            raise ValueError("similarity_matrix must be a numpy array")
        if similarity_matrix.ndim != 2 or similarity_matrix.shape[0] != similarity_matrix.shape[1]:
            raise ValueError("similarity_matrix must be a square matrix")
        if not isinstance(n_clusters, int) or n_clusters < 1:
            raise ValueError("n_clusters must be a positive integer")

        n_samples = similarity_matrix.shape[0]

        # Edge cases
        if n_samples == 0:
            return {"labels": np.array([], dtype=int)}
        if n_clusters == 1:
            return {"labels": np.zeros(n_samples, dtype=int)}
        if n_clusters >= n_samples:
            return {"labels": np.arange(n_samples, dtype=int)}

        # Compute normalized Laplacian
        deg = similarity_matrix.sum(axis=1)
        # Avoid division by zero
        with np.errstate(divide="ignore"):
            inv_sqrt_deg = 1.0 / np.sqrt(np.maximum(deg, 1e-12))
        D_half = np.diag(inv_sqrt_deg)
        L = np.eye(n_samples) - D_half @ similarity_matrix @ D_half

        # Eigen decomposition: compute first k eigenvectors
        try:
            # Use dense eigh for moderate sizes; fallback to eigsh for large n
            if n_samples <= 2000:
                evals, evecs = np.linalg.eigh(L)
                # Sort ascending
                idx = np.argsort(evals)
                evecs = evecs[:, idx]
                U = evecs[:, :n_clusters]
            else:
                from scipy.sparse.linalg import eigsh
                evals, evecs = eigsh(L, k=n_clusters, which="SM")
                # eigsh may not return sorted; sort
                idx = np.argsort(evals)
                evecs = evecs[:, idx]
                U = evecs[:, :n_clusters]
        except Exception:
            # Fallback: use all eigenvectors and take first k
            evals, evecs = np.linalg.eigh(L)
            idx = np.argsort(evals)
            evecs = evecs[:, idx]
            U = evecs[:, :n_clusters]

        # Row-normalize
        norms = np.linalg.norm(U, axis=1, keepdims=True)
        norms[norms == 0] = 1.0
        U_norm = U / norms

        # KMeans on embedded space
        kmeans = KMeans(n_clusters=n_clusters, random_state=42, n_init=10, max_iter=300)
        labels = kmeans.fit_predict(U_norm)

        return {"labels": labels}