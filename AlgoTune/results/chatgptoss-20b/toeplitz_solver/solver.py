from typing import Any
import numpy as np
from scipy.linalg import solve_toeplitz

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the linear system Tx = b where T is a Toeplitz matrix defined by
        its first column `c` and first row `r`. The solution is computed using
        scipy's efficient Levinson-Durbin implementation.

        Parameters
        ----------
        problem : dict
            Dictionary with keys:
                - "c": list[float] first column of T
                - "r": list[float] first row of T
                - "b": list[float] right-hand side vector
        kwargs : dict
            Additional keyword arguments (ignored).

        Returns
        -------
        list[float]
            Solution vector x such that Tx = b.
        """
        # Convert inputs to numpy arrays for efficient computation
        c = np.asarray(problem["c"], dtype=np.float64)
        r = np.asarray(problem["r"], dtype=np.float64)
        b = np.asarray(problem["b"], dtype=np.float64)

        # Solve using Levinson-Durbin algorithm
        x = solve_toeplitz((c, r), b)

        # Return as plain Python list
        return x.tolist()