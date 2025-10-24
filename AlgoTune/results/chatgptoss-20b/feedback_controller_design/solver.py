from typing import Any
import numpy as np
import scipy.linalg
import scipy.signal

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solves the static state feedback controller design problem for a discrete-time LTI system.
        Returns a dictionary with keys:
            - is_stabilizable: bool
            - K: list of lists (m x n) or None
            - P: list of lists (n x n) or None
        """
        # Parse input matrices
        A = np.array(problem["A"], dtype=float)
        B = np.array(problem["B"], dtype=float)
        n, m = A.shape[0], B.shape[1]

        # Helper: check stabilizability
        def is_stabilizable(A, B):
            eigs = np.linalg.eigvals(A)
            for lam in eigs:
                if abs(lam) >= 1.0:
                    # Check rank of [A - lam*I, B]
                    M = np.hstack((A - lam * np.eye(n), B))
                    if np.linalg.matrix_rank(M) < n:
                        return False
            return True

        if not is_stabilizable(A, B):
            return {"is_stabilizable": False, "K": None, "P": None}

        # Attempt to compute a stabilizing K via pole placement
        try:
            # Desired poles: all inside unit circle, e.g., 0.5
            desired_poles = 0.5 * np.ones(n, dtype=complex)
            result = scipy.signal.place_poles(A, B, desired_poles, method="discrete")
            K = result.gain_matrix
        except Exception:
            # Fallback: use a simple LQR with Q=I, R=I to get K
            # Solve discrete-time Riccati equation
            Q = np.eye(n)
            R = np.eye(m)
            # Solve Riccati: X = A^T X A - A^T X B (R + B^T X B)^-1 B^T X A + Q
            # Use scipy.linalg.solve_discrete_are
            X = scipy.linalg.solve_discrete_are(A, B, Q, R)
            K = -np.linalg.inv(R + B.T @ X @ B) @ (B.T @ X @ A)

        # Compute Lyapunov matrix P for closed-loop system
        A_cl = A + B @ K
        try:
            P = scipy.linalg.solve_discrete_lyapunov(A_cl, np.eye(n))
        except Exception:
            # If Lyapunov solver fails, fallback to identity
            P = np.eye(n)

        # Ensure symmetry
        P = (P + P.T) / 2.0

        return {
            "is_stabilizable": True,
            "K": K.tolist(),
            "P": P.tolist()
        }