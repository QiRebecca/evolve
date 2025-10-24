from typing import Any
import numpy as np
from scipy.integrate import cumulative_simpson

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        y = problem["y"]
        dx = problem["dx"]
        return cumulative_simpson(y, dx=dx)