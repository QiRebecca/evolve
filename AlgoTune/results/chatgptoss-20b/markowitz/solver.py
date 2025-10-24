from typing import Any
import numpy as np
import cvxpy as cp
import logging

class Solver:
    def solve(self, problem: dict[str, Any], **kwargs) -> Any:
        """
        Solve the Markowitz portfolio optimization problem:
            maximize μ^T w - γ * w^T Σ w
            subject to 1^T w = 1, w >= 0
        """
        # Extract data
        μ = np.asarray(problem["μ"], dtype=float)
        Σ = np.asarray(problem["Σ"], dtype=float)
        γ = float(problem["γ"])
        n = μ.size

        # Define variable
        w = cp.Variable(n)

        # Objective: maximize μ^T w - γ * w^T Σ w
        # cvxpy minimizes, so we use -objective
        objective = cp.Maximize(μ @ w - γ * cp.quad_form(w, cp.psd_wrap(Σ)))

        # Constraints
        constraints = [cp.sum(w) == 1, w >= 0]

        # Build problem
        prob = cp.Problem(objective, constraints)

        # Try OSQP first for speed; fallback to default if fails
        try:
            prob.solve(solver=cp.OSQP, verbose=False, eps_abs=1e-8, eps_rel=1e-8)
        except Exception:
            try:
                prob.solve(verbose=False)
            except Exception as e:
                logging.error("Solver failed: %s", e)
                return None

        # Validate solution
        if w.value is None or not np.isfinite(w.value).all():
            logging.warning("No finite solution returned.")
            return None

        return {"w": w.value.tolist()}