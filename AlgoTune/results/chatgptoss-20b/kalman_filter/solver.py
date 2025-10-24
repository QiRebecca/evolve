from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the Kalman filtering/smoothing problem formulated as a QP
        using an analytical least‑squares approach.
        """
        # Extract problem data
        A = np.asarray(problem["A"], dtype=float)
        B = np.asarray(problem["B"], dtype=float)
        C = np.asarray(problem["C"], dtype=float)
        y = np.asarray(problem["y"], dtype=float)
        x0 = np.asarray(problem["x_initial"], dtype=float)
        tau = float(problem["tau"])

        N, m = y.shape
        n = A.shape[1]
        p = B.shape[1]

        # Handle trivial case
        if N == 0:
            return {
                "x_hat": [x0.tolist()],
                "w_hat": [],
                "v_hat": []
            }

        # Precompute powers of A
        A_powers = [np.eye(n, dtype=float)]
        for t in range(1, N + 1):
            A_powers.append(A_powers[-1] @ A)

        # Build measurement matrix M (size N*m x N*p)
        M = np.zeros((N * m, N * p), dtype=float)
        for t in range(N):
            for k in range(t):
                # Contribution of w_k to measurement at time t
                block = C @ A_powers[t - 1 - k] @ B
                M[t * m:(t + 1) * m, k * p:(k + 1) * p] = block

        # Build RHS vector
        y_vec = y.reshape(-1)  # shape (N*m,)
        y_minus = np.empty_like(y_vec)
        for t in range(N):
            y_minus[t * m:(t + 1) * m] = y[t] - (C @ A_powers[t] @ x0)

        # Solve normal equations: (I + tau M^T M) w = tau M^T (y - C A^t x0)
        MTM = M.T @ M
        A_mat = np.eye(N * p, dtype=float) + tau * MTM
        b_vec = tau * (M.T @ y_minus)

        try:
            w_vec = np.linalg.solve(A_mat, b_vec)
        except np.linalg.LinAlgError:
            # Fallback to least squares if singular
            w_vec, *_ = np.linalg.lstsq(A_mat, b_vec, rcond=None)

        w_hat = w_vec.reshape(N, p)

        # Reconstruct state and measurement noise sequences
        x_hat = [x0]
        v_hat = []
        for t in range(N):
            x_next = A @ x_hat[-1] + B @ w_hat[t]
            x_hat.append(x_next)
            v_hat.append(y[t] - C @ x_hat[-2])

        # Convert to lists of lists
        return {
            "x_hat": [x.tolist() for x in x_hat],
            "w_hat": [w.tolist() for w in w_hat],
            "v_hat": [v.tolist() for v in v_hat]
        }