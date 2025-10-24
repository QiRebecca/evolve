from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the sparse PCA problem using a fast per-component algorithm.
        """
        A = np.array(problem["covariance"])
        n_components = int(problem["n_components"])
        sparsity_param = float(problem["sparsity_param"])

        n = A.shape[0]

        # Eigendecomposition of covariance matrix
        eigvals, eigvecs = np.linalg.eigh(A)

        # Keep only positive eigenvalues
        pos_mask = eigvals > 0
        eigvals = eigvals[pos_mask]
        eigvecs = eigvecs[:, pos_mask]

        # Sort in descending order
        idx = np.argsort(eigvals)[::-1]
        eigvals = eigvals[idx]
        eigvecs = eigvecs[:, idx]

        k = min(len(eigvals), n_components)
        B = eigvecs[:, :k] * np.sqrt(eigvals[:k])

        # Pad B if necessary to match n_components
        if n_components > k:
            B = np.hstack([B, np.zeros((n, n_components - k))])
        elif n_components < k:
            B = B[:, :n_components]

        # Helper: soft-thresholding
        def soft_threshold(b, thresh):
            return np.sign(b) * np.maximum(np.abs(b) - thresh, 0.0)

        X = np.zeros((n, n_components))

        for i in range(n_components):
            b = B[:, i]
            # Unconstrained solution
            x_un = soft_threshold(b, sparsity_param / 2.0)
            norm_un = np.linalg.norm(x_un)

            if norm_un <= 1.0:
                X[:, i] = x_un
                continue

            # Need to solve constrained problem via root finding on μ
            def g(mu):
                denom = 1.0 + mu
                thresh = sparsity_param / (2.0 * denom)
                x_mu = soft_threshold(b / denom, thresh)
                return np.linalg.norm(x_mu) - 1.0

            # Find upper bound
            low = 0.0
            high = 1.0
            while g(high) > 0.0:
                high *= 2.0

            # Binary search
            tol = 1e-8
            while high - low > tol:
                mid = (low + high) / 2.0
                if g(mid) > 0.0:
                    low = mid
                else:
                    high = mid

            mu_opt = high
            denom = 1.0 + mu_opt
            thresh = sparsity_param / (2.0 * denom)
            X[:, i] = soft_threshold(b / denom, thresh)

        # Compute explained variance
        explained_variance = []
        for i in range(n_components):
            comp = X[:, i]
            var = comp.T @ A @ comp
            explained_variance.append(float(var))

        return {"components": X.tolist(), "explained_variance": explained_variance}