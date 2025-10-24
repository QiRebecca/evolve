from typing import Any
import numpy as np
from scipy.optimize import minimize, LinearConstraint, Bounds

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve a convex quadratic program in standard form:
            minimize 0.5 * x^T P x + q^T x
            subject to Gx <= h
                       Ax == b
        Parameters
        ----------
        problem : dict
            Dictionary containing keys "P", "q", "G", "h", "A", "b".
        Returns
        -------
        dict
            Dictionary with keys "solution" (list of floats) and
            "objective" (float) containing the optimal value.
        """
        # Convert inputs to numpy arrays
        P = np.asarray(problem["P"], dtype=float)
        q = np.asarray(problem["q"], dtype=float)
        G = np.asarray(problem["G"], dtype=float)
        h = np.asarray(problem["h"], dtype=float)
        A = np.asarray(problem["A"], dtype=float)
        b = np.asarray(problem["b"], dtype=float)

        # Ensure P is symmetric
        P = (P + P.T) / 2.0

        n = P.shape[0]

        # Objective function and gradient
        def fun(x):
            return 0.5 * x @ P @ x + q @ x

        def grad(x):
            return P @ x + q

        # Hessian (constant)
        def hess(x):
            return P

        # Linear inequality constraints Gx <= h
        if G.size > 0:
            lin_ineq = LinearConstraint(G, -np.inf, h)
        else:
            lin_ineq = None

        # Linear equality constraints Ax == b
        if A.size > 0:
            lin_eq = LinearConstraint(A, b, b)
        else:
            lin_eq = None

        # Combine constraints
        constraints = []
        if lin_ineq is not None:
            constraints.append(lin_ineq)
        if lin_eq is not None:
            constraints.append(lin_eq)

        # Initial guess: zero vector
        x0 = np.zeros(n)

        # Run the optimizer
        res = minimize(
            fun,
            x0,
            method="trust-constr",
            jac=grad,
            hess=hess,
            constraints=constraints,
            options={
                "gtol": 1e-8,
                "xtol": 1e-8,
                "maxiter": 1000,
                "verbose": 0,
            },
        )

        if not res.success:
            raise ValueError(f"Solver failed: {res.message}")

        solution = res.x
        objective = res.fun

        return {"solution": solution.tolist(), "objective": float(objective)}