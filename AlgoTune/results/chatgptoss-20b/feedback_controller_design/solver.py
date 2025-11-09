from typing import Any
import numpy as np
from scipy.linalg import solve_discrete_are

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solves the static state feedback controller design problem for a discrete-time LTI system.
        Uses controllability test for stabilizability and discrete-time LQR (Q=I, R=I) to obtain
        a stabilizing gain K and Lyapunov matrix P.

        Parameters
        ----------
        problem : dict
            Dictionary containing 'A' and 'B' matrices.

        Returns
        -------
        dict
            Dictionary with keys:
                - 'is_stabilizable': bool
                - 'K': list of lists (m x n) or None
                - 'P': list of lists (n x n) or None
        """
        try:
            A = np.array(problem["A"], dtype=float)
            B = np.array(problem["B"], dtype=float)
        except Exception as e:
            return {"is_stabilizable": False, "K": None, "P": None}

        n = A.shape[0]
        m = B.shape[1]

        # Check stabilizability via controllability matrix rank
        try:
            # Build controllability matrix [B, AB, A^2B, ..., A^(n-1)B]
            ctrb = B
            for i in range(1, n):
                ctrb = np.hstack((ctrb, np.linalg.matrix_power(A, i) @ B))
            rank_ctrb = np.linalg.matrix_rank(ctrb)
            is_stabilizable = rank_ctrb == n
        except Exception:
            return {"is_stabilizable": False, "K": None, "P": None}

        if not is_stabilizable:
            return {"is_stabilizable": False, "K": None, "P": None}

        # Use discrete-time LQR with Q=I, R=I to obtain stabilizing K and P
        try:
            Q = np.eye(n)
            R = np.eye(m)
            P = solve_discrete_are(A, B, Q, R)
            # Compute K = -(R + B^T P B)^-1 B^T P A
            BT_P = B.T @ P
            inv_term = np.linalg.inv(R + BT_P @ B)
            K = -inv_term @ BT_P @ A
        except Exception:
            return {"is_stabilizable": False, "K": None, "P": None}

        # Ensure P is symmetric
        if not np.allclose(P, P.T, rtol=1e-5, atol=1e-8):
            return {"is_stabilizable": False, "K": None, "P": None}

        return {
            "is_stabilizable": True,
            "K": K.tolist(),
            "P": P.tolist()
        }