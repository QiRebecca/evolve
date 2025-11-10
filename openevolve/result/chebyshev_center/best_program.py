import logging
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
from scipy.optimize import linprog

# The following imports come from the evaluation harness.
from AlgoTuneTasks.base import register_task, Task


@register_task("chebyshev_center")
class ChebyshevCenterTask(Task):
    """
    Task: Find the Chebyshev center (center of the largest inscribed Euclidean ball)
    of a polyhedron  P = { x | a_i^T x <= b_i , i = 1,…,m }.

    The classical LP reformulation is:

        maximize     r
        subject to   a_i^T x + r * ||a_i||_2 <= b_i   for i = 1,…,m
                     r >= 0

    Decision variables: x ∈ R^n (center) and r ∈ R (radius).
    """

    # No heavy work in __init__; compile-time is free but we keep it minimal.
    def __init__(self, **kwargs):
        super().__init__(**kwargs)

    # ------------------------------------------------------------------ #
    # Helper: build a random problem instance (unchanged from baseline)   #
    # ------------------------------------------------------------------ #
    def generate_problem(self, n: int, random_seed: int = 1) -> Dict[str, Any]:
        logging.debug(
            "Generating Chebyshev center problem with n=%d, seed=%d", n, random_seed
        )
        rng = np.random.default_rng(random_seed)
        n += 1  # keep original behaviour

        m = n // 2
        x_star = rng.standard_normal(n)
        a = rng.standard_normal((m, n))
        a = np.vstack((a, -a))
        b = a @ x_star + rng.random(a.shape[0])  # ensure feasibility

        return {"a": a.tolist(), "b": b.tolist()}

    # ------------------------------------------------------------------ #
    # Core solver: uses SciPy HiGHS LP solver for speed                  #
    # ------------------------------------------------------------------ #
    def solve(self, problem: Dict[str, Any], **kwargs) -> Dict[str, List[float]]:
        """
        Solve the Chebyshev center problem via linear programming with SciPy/HiGHS.

        Parameters
        ----------
        problem : dict
            Must contain keys
              - "a": list (m x n) of floats
              - "b": list (m,) of floats

        Returns
        -------
        dict
            {"solution": list of length n} – optimal Chebyshev center.
        """
        a = np.asarray(problem["a"], dtype=float)
        b = np.asarray(problem["b"], dtype=float)

        m, n = a.shape
        # Variable ordering: [x_0, …, x_{n-1}, r]
        num_vars = n + 1

        # Objective: maximise r  ⇒  minimise -r
        c = np.zeros(num_vars)
        c[-1] = -1.0  # coefficient for -r

        # Build inequality constraints  A_ub @ [x ; r] <= b
        a_norm = np.linalg.norm(a, axis=1)
        A_ub = np.hstack((a, a_norm[:, None]))  # shape (m, n+1)
        b_ub = b

        # Bounds: x free, r ≥ 0
        bounds: List[Tuple[Optional[float], Optional[float]]] = [(None, None)] * n + [
            (0.0, None)
        ]

        # Solve with HiGHS (fast, default)
        res = linprog(
            c,
            A_ub=A_ub,
            b_ub=b_ub,
            bounds=bounds,
            method="highs",
            options={"presolve": "on"},
        )

        if res.status != 0:
            # 0 == optimal in HiGHS / linprog
            raise RuntimeError(f"LP solver failed: {res.message}")

        # Extract x (center); r is res.x[-1] but not required for output
        x_opt = res.x[:-1]
        return {"solution": x_opt.tolist()}

    # ------------------------------------------------------------------ #
    # Validator (unchanged, relies on self.solve)                        #
    # ------------------------------------------------------------------ #
    def is_solution(self, problem: Dict[str, Any], solution: Dict[str, List]) -> bool:
        proposed_solution = solution.get("solution")
        if proposed_solution is None:
            logging.error("Solution dict missing 'solution' key.")
            return False

        # Compute reference solution using our own solver
        real_solution = np.array(self.solve(problem)["solution"])
        a = np.asarray(problem["a"], dtype=float)
        b = np.asarray(problem["b"], dtype=float)

        def radius(center: np.ndarray) -> float:
            return np.min((b - a @ center) / np.linalg.norm(a, axis=1))

        real_radius = radius(real_solution)
        prop_radius = radius(np.array(proposed_solution))

        if not np.allclose(real_radius, prop_radius, atol=1e-6):
            logging.error(
                "Proposed solution radius %.6e != reference %.6e",
                prop_radius,
                real_radius,
            )
            return False
        return True