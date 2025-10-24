from typing import Any
import numpy as np
import cvxpy as cp

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the projection onto the CVaR constraint set using a
        quadratic program with linear constraints. This formulation
        replaces the sum_largest operator with auxiliary variables,
        which is typically faster for CVXPY.
        """
        # Extract problem data
        x0 = np.array(problem["x0"])
        A = np.array(problem["loss_scenarios"])
        beta = float(problem.get("beta", 0.95))
        kappa = float(problem.get("kappa", 0.0))

        n_scenarios, n_dims = A.shape
        k = int((1 - beta) * n_scenarios)
        alpha = kappa * k

        # Variables
        x = cp.Variable(n_dims)
        if k > 0:
            t = cp.Variable()
            u = cp.Variable(n_scenarios)
            constraints = [
                A @ x - t <= u,
                u >= 0,
                cp.sum(u) <= alpha
            ]
        else:
            # If k == 0, the CVaR constraint is always satisfied
            constraints = []

        # Objective: minimize squared Euclidean distance to x0
        objective = cp.Minimize(cp.sum_squares(x - x0))

        # Solve the problem
        prob = cp.Problem(objective, constraints)
        try:
            prob.solve(solver=cp.OSQP, verbose=False, eps_abs=1e-8, eps_rel=1e-8)
            if prob.status not in {cp.OPTIMAL, cp.OPTIMAL_INACCURATE} or x.value is None:
                return {"x_proj": []}
            return {"x_proj": x.value.tolist()}
        except Exception:
            return {"x_proj": []}