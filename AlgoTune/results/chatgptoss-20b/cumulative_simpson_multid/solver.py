from typing import Any
from scipy.integrate import cumulative_simpson

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the cumulative integral along the last axis of the multi-dimensional array using Simpson's rule.
        """
        y2 = problem["y2"]
        dx = problem["dx"]
        return cumulative_simpson(y2, dx=dx)