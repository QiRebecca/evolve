from typing import Any
import numpy as np

class Solver:
    def solve(self, problem: dict[str, Any], **kwargs) -> Any:
        """
        Compute optimal control sequence via backward Riccati recursion.
        Returns dict with key "U" (shape (T, m)).
        """
        # Convert inputs to numpy arrays
        A = np.asarray(problem["A"], dtype=float)
        B = np.asarray(problem["B"], dtype=float)
        Q = np.asarray(problem["Q"], dtype=float)
        R = np.asarray(problem["R"], dtype=float)
        P = np.asarray(problem["P"], dtype=float)
        T = int(problem["T"])
        x0 = np.asarray(problem["x0"], dtype=float).reshape(-1, 1)

        n, m = B.shape
        S = np.zeros((T + 1, n, n), dtype=float)
        K = np.zeros((T, m, n), dtype=float)
        S[T] = P

        for t in range(T - 1, -1, -1):
            St1 = S[t + 1]
            M1 = R + B.T @ St1 @ B
            M2 = B.T @ St1 @ A
            try:
                K[t] = np.linalg.solve(M1, M2)
            except np.linalg.LinAlgError:
                K[t] = np.linalg.pinv(M1) @ M2
            Acl = A - B @ K[t]
            S[t] = Q + K[t].T @ R @ K[t] + Acl.T @ St1 @ Acl
            # Ensure symmetry
            S[t] = (S[t] + S[t].T) * 0.5

        U = np.zeros((T, m), dtype=float)
        x = x0
        for t in range(T):
            u = -K[t] @ x
            U[t] = u.ravel()
            x = A @ x + B @ u

        return {"U": U}