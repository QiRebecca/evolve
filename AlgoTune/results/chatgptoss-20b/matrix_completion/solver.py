from typing import Any
import numpy as np
import cvxpy as cp

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solves the Perron-Frobenius matrix completion using CVXPY with the SCS solver
        for improved speed while maintaining solution accuracy within the required tolerance.
        """
        inds = np.array(problem["inds"])
        a = np.array(problem["a"])
        n = problem["n"]

        # Generate all indices and determine missing indices
        xx, yy = np.meshgrid(np.arange(n), np.arange(n))
        allinds = np.vstack((yy.flatten(), xx.flatten())).T
        # Boolean mask for observed indices
        mask = np.isin(allinds, inds, assume_unique=False).all(axis=1)
        otherinds = allinds[~mask]

        # Define CVXPY variable
        B = cp.Variable((n, n), pos=True)

        # Objective: minimize Perron-Frobenius eigenvalue
        objective = cp.Minimize(cp.pf_eigenvalue(B))

        # Constraints
        constraints = [
            cp.prod(B[otherinds[:, 0], otherinds[:, 1]]) == 1.0,
            B[inds[:, 0], inds[:, 1]] == a,
        ]

        # Solve with SCS solver for speed
        prob = cp.Problem(objective, constraints)
        try:
            result = prob.solve(solver=cp.SCS, eps=1e-5, max_iters=5000, verbose=False, gp=True)
        except cp.SolverError as e:
            return None
        except Exception:
            return None

        if prob.status not in [cp.OPTIMAL, cp.OPTIMAL_INACCURATE]:
            return None

        if B.value is None:
            return None

        return {
            "B": B.value.tolist(),
            "optimal_value": result,
        }