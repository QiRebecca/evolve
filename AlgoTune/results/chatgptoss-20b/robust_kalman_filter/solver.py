from typing import Any
import numpy as np
import cvxpy as cp

class Solver:
    def solve(self, problem: dict[str, Any], **kwargs) -> Any:
        """
        Solve the robust Kalman filtering problem using the Huber loss function.
        This implementation uses CVXPY with the ECOS solver for improved speed.
        """
        # Extract problem data
        A = np.array(problem["A"])
        B = np.array(problem["B"])
        C = np.array(problem["C"])
        y = np.array(problem["y"])
        x0 = np.array(problem["x_initial"])
        tau = float(problem["tau"])
        M = float(problem["M"])

        N, m = y.shape
        n = A.shape[1]
        p = B.shape[1]

        # Variables: x[0]...x[N], w[0]...w[N-1], v[0]...v[N-1]
        x = cp.Variable((N + 1, n), name="x")
        w = cp.Variable((N, p), name="w")
        v = cp.Variable((N, m), name="v")

        # Objective: minimize sum_{t=0}^{N-1}(||w_t||_2^2 + tau * phi(v_t))
        process_noise_term = cp.sum_squares(w)
        # Use vectorized Huber on the norms of v rows
        measurement_noise_term = tau * cp.sum(cp.huber(cp.norm(v, axis=1), M))
        obj = cp.Minimize(process_noise_term + measurement_noise_term)

        # Constraints
        constraints = [x[0] == x0]  # Initial state

        # Add dynamics and measurement constraints
        for t in range(N):
            constraints.append(x[t + 1] == A @ x[t] + B @ w[t])  # Dynamics
            constraints.append(y[t] == C @ x[t] + v[t])          # Measurement

        # Solve the problem using ECOS solver
        prob = cp.Problem(obj, constraints)
        try:
            prob.solve(solver=cp.ECOS, verbose=False, max_iters=1000)
        except cp.SolverError as e:
            # If ECOS fails, fall back to default solver
            try:
                prob.solve()
            except Exception:
                return {"x_hat": [], "w_hat": [], "v_hat": []}
        except Exception:
            return {"x_hat": [], "w_hat": [], "v_hat": []}

        if prob.status not in {cp.OPTIMAL, cp.OPTIMAL_INACCURATE} or x.value is None:
            return {"x_hat": [], "w_hat": [], "v_hat": []}

        return {
            "x_hat": x.value.tolist(),
            "w_hat": w.value.tolist(),
            "v_hat": v.value.tolist(),
        }