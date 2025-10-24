from typing import Any
import numpy as np
from scipy.optimize import linprog

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the optimal power control problem using a linear programming
        formulation. The problem is:
            minimize sum(P)
            subject to:
                P_min <= P <= P_max
                G_ii * P_i >= S_min * (σ_i + sum_{k!=i} G_ik * P_k)
        This can be rewritten as linear inequalities and solved with
        scipy.optimize.linprog for speed.
        """
        G = np.asarray(problem["G"], dtype=float)
        sigma = np.asarray(problem["σ"], dtype=float)
        P_min = np.asarray(problem["P_min"], dtype=float)
        P_max = np.asarray(problem["P_max"], dtype=float)
        S_min = float(problem["S_min"])
        n = G.shape[0]

        # Objective: minimize sum(P)
        c = np.ones(n)

        # Inequality constraints: -Gii * Pi + S_min * sum_{k!=i} Gik * Pk <= -S_min * sigma_i
        A_ub = np.empty((n, n), dtype=float)
        b_ub = np.empty(n, dtype=float)
        for i in range(n):
            # Start with zeros
            row = np.zeros(n, dtype=float)
            # Diagonal term
            row[i] = -G[i, i]
            # Off-diagonal terms
            if n > 1:
                # All columns except i
                idx = np.arange(n) != i
                row[idx] = S_min * G[i, idx]
            A_ub[i] = row
            b_ub[i] = -S_min * sigma[i]

        # Bounds for each variable
        bounds = [(P_min[i], P_max[i]) for i in range(n)]

        # Solve LP
        res = linprog(c, A_ub=A_ub, b_ub=b_ub, bounds=bounds, method="highs")

        if res.status != 0:
            # status 0 means optimal, others indicate infeasible, unbounded, etc.
            raise ValueError(f"Linear solver failed (status={res.status})")

        P_opt = res.x
        obj_opt = res.fun

        return {"P": P_opt.tolist(), "objective": float(obj_opt)}