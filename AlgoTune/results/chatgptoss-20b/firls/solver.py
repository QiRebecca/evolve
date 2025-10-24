from typing import Any
import numpy as np
from scipy import signal

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        n, edges = problem
        n = 2 * n + 1
        edges = tuple(edges)
        coeffs = signal.firls(n, (0.0, *edges, 1.0), [1, 1, 0, 0])
        return coeffs