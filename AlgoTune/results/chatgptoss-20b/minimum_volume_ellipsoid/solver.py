import numpy as np
from typing import Any

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the minimum volume covering ellipsoid problem using the Khachiyan algorithm.
        """
        points = np.array(problem["points"])
        n, d = points.shape

        # Compute center and shape matrix of the MVEE
        c, A = self._mv_ellipsoid(points)

        # Compute symmetric positive definite X such that X^2 = A
        eigvals, eigvecs = np.linalg.eigh(A)
        # Ensure numerical non-negativity
        eigvals = np.maximum(eigvals, 0.0)
        sqrt_vals = np.sqrt(eigvals)
        X = eigvecs @ np.diag(sqrt_vals) @ eigvecs.T

        # Compute Y = -X * c
        Y = -X @ c

        # Objective value: -log det X
        obj = -np.log(np.linalg.det(X))

        return {
            "objective_value": float(obj),
            "ellipsoid": {"X": X.tolist(), "Y": Y.tolist()}
        }

    @staticmethod
    def _mv_ellipsoid(points: np.ndarray, tol: float = 1e-5, max_iter: int = 1000) -> tuple[np.ndarray, np.ndarray]:
        """
        Compute the minimum volume enclosing ellipsoid (MVEE) of a set of points.
        Returns the center c and the shape matrix A such that the ellipsoid is
        {x | (x - c)^T A (x - c) <= 1}.
        """
        n, d = points.shape
        # Augment points with a column of ones
        Q = np.hstack((points, np.ones((n, 1))))  # n x (d+1)
        u = np.full(n, 1.0 / n)  # initial weights

        for _ in range(max_iter):
            # Compute weighted covariance matrix
            X_mat = (Q.T * u) @ Q  # (d+1) x (d+1)
            # Solve X_mat * Y = Q.T for Y
            invXQ = np.linalg.solve(X_mat, Q.T)  # (d+1) x n
            # Compute M = diag(Q * invXQ.T)
            M = np.sum(Q * invXQ.T, axis=1)
            j = np.argmax(M)
            step_size = (M[j] - d - 1) / ((d + 1) * (M[j] - 1))
            if step_size <= 0:
                break
            new_u = (1 - step_size) * u
            new_u[j] += step_size
            if np.linalg.norm(new_u - u) < tol:
                u = new_u
                break
            u = new_u

        # Center of the ellipsoid
        c = points.T @ u  # d

        # Compute shape matrix A
        diff = points - c  # n x d
        S = diff.T @ (diff * u[:, None])  # d x d
        # Regularize in case of numerical issues
        if np.linalg.matrix_rank(S) < d:
            S += 1e-12 * np.eye(d)
        A = np.linalg.inv(S) / d

        return c, A