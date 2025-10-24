from typing import Any
import numpy as np
import cvxpy as cp
import logging

class Solver:
    def solve(self, problem: dict[str, Any], **kwargs) -> Any:
        """Solve the queuing system optimization problem.

        Parameters
        ----------
        problem : dict
            Dictionary containing problem data with keys:
            - "w_max": list of max waiting times
            - "d_max": list of max total delays
            - "q_max": list of max queue occupancies
            - "λ_min": list of minimum arrival rates
            - "μ_max": scalar maximum total service rate
            - "γ": list of objective weights

        Returns
        -------
        dict
            Dictionary with keys:
            - "μ": optimal service rates (numpy array)
            - "λ": optimal arrival rates (numpy array)
            - "objective": optimal objective value (float)
        """
        # Convert inputs to numpy arrays
        w_max = np.asarray(problem["w_max"])
        d_max = np.asarray(problem["d_max"])
        q_max = np.asarray(problem["q_max"])
        λ_min = np.asarray(problem["λ_min"])
        μ_max = float(problem["μ_max"])
        γ = np.asarray(problem["γ"])
        n = γ.size

        # Define variables
        μ = cp.Variable(n, pos=True)
        λ = cp.Variable(n, pos=True)
        ρ = λ / μ  # server load

        # Queue metrics
        q = cp.power(ρ, 2) / (1 - ρ)
        w = q / λ + 1 / μ
        d = 1 / (μ - λ)

        # Constraints
        constraints = [
            w <= w_max,
            d <= d_max,
            q <= q_max,
            λ >= λ_min,
            cp.sum(μ) <= μ_max,
        ]

        # Objective
        obj = cp.Minimize(γ @ (μ / λ))

        # Problem
        prob = cp.Problem(obj, constraints)

        # Solve with geometric programming first
        try:
            prob.solve(gp=True, **kwargs)
        except cp.error.DGPError:
            logging.warning("QueuingTask: DGP solve failed—trying DCP.")
            try:
                prob.solve(**kwargs)
            except cp.error.DCPError:
                logging.warning("QueuingTask: DCP solve failed—using heuristic fallback.")
                # Heuristic fallback: λ = λ_min, μ = μ_max/n
                λ_val = λ_min
                μ_val = np.full(n, μ_max / n)
                obj_val = float(γ @ (μ_val / λ_val))
                return {"μ": μ_val, "λ": λ_val, "objective": obj_val}

        # Check status
        if prob.status not in (cp.OPTIMAL, cp.OPTIMAL_INACCURATE):
            raise ValueError(f"Solver failed with status {prob.status}")

        return {
            "μ": μ.value,
            "λ": λ.value,
            "objective": float(prob.value),
        }