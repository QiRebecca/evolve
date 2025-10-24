from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the entropically regularized optimal transport plan using the Sinkhorn algorithm.
        """
        try:
            a = np.asarray(problem["source_weights"], dtype=np.float64)
            b = np.asarray(problem["target_weights"], dtype=np.float64)
            M = np.ascontiguousarray(problem["cost_matrix"], dtype=np.float64)
            reg = float(problem["reg"])

            # Parameters matching POT's default
            max_iter = 1000
            stop_thr = 1e-9
            eps = 1e-16

            # Compute kernel matrix
            K = np.exp(-M / reg)

            # Initialize scaling vectors
            u = np.ones_like(a)
            v = np.ones_like(b)

            for _ in range(max_iter):
                u_prev = u.copy()
                v_prev = v.copy()

                K_v = K @ v
                K_v = np.where(K_v == 0, eps, K_v)
                u = a / K_v

                K_T_u = K.T @ u
                K_T_u = np.where(K_T_u == 0, eps, K_T_u)
                v = b / K_T_u

                if np.allclose(u, u_prev, rtol=stop_thr) and np.allclose(v, v_prev, rtol=stop_thr):
                    break

            G = np.outer(u, v) * K

            if not np.isfinite(G).all():
                raise ValueError("Non‑finite values in transport plan")

            return {"transport_plan": G, "error_message": None}
        except Exception as exc:
            return {"transport_plan": None, "error_message": str(exc)}