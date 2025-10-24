from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the LP centering problem:
            minimize   c^T x - sum(log x_i)
            subject to Ax = b, x > 0
        using a Newton method on the KKT conditions.
        """
        c = np.array(problem["c"], dtype=np.float64)
        A = np.array(problem["A"], dtype=np.float64)
        b = np.array(problem["b"], dtype=np.float64)

        m, n = A.shape
        # Initial dual variable
        lam = np.zeros(m, dtype=np.float64)
        eps = 1e-12
        max_iter = 50
        tol = 1e-8

        for _ in range(max_iter):
            w = c + A.T @ lam
            # Ensure positivity of w
            if np.any(w <= 0):
                # Shift lam slightly to keep w positive
                lam += eps
                w = c + A.T @ lam
            x = 1.0 / w
            f = A @ x - b
            if np.linalg.norm(f, ord=np.inf) < tol:
                break

            # Jacobian: J = -A * diag(1/w^2) * A^T
            v = 1.0 / (w ** 2)
            B = A * v  # each column of A scaled by v
            J = -B @ A.T

            try:
                delta_lam = np.linalg.solve(J, -f)
            except np.linalg.LinAlgError:
                delta_lam = np.linalg.lstsq(J, -f, rcond=None)[0]

            # Backtracking line search to maintain positivity of w
            alpha = 1.0
            for _ in range(20):
                lam_new = lam + alpha * delta_lam
                w_new = c + A.T @ lam_new
                if np.all(w_new > 0):
                    lam = lam_new
                    break
                alpha *= 0.5
            else:
                # If no feasible step found, exit
                break

        x = 1.0 / (c + A.T @ lam)
        return {"solution": x.tolist()}