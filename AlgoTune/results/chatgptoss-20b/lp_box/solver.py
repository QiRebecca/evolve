from typing import Any
import numpy as np
from scipy.optimize import linprog

class Solver:
    def solve(self, problem: dict[str, Any], **kwargs) -> Any:
        """
        Solve the LP box problem using SciPy's linprog with the HiGHS solver.

        Parameters
        ----------
        problem : dict
            Dictionary containing keys 'c', 'A', and 'b' defining the LP.

        Returns
        -------
        dict
            Dictionary with key 'solution' containing the optimal x as a list.
        """
        # Extract problem data
        c = np.asarray(problem["c"], dtype=np.float64)
        A = np.asarray(problem["A"], dtype=np.float64)
        b = np.asarray(problem["b"], dtype=np.float64)

        # Number of variables
        n = c.size

        # Bounds for each variable: 0 <= x_i <= 1
        bounds = [(0.0, 1.0)] * n

        # Solve the LP
        res = linprog(
            c=c,
            A_ub=A,
            b_ub=b,
            bounds=bounds,
            method="highs",
            options={"presolve": True}
        )

        # Ensure the solution is optimal
        if res.status != 0:
            raise RuntimeError(f"Linear program did not solve to optimality: {res.message}")

        # Return the solution as a list
        return {"solution": res.x.tolist()}