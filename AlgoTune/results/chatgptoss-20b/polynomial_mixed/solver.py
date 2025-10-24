from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the polynomial problem by finding all roots of the polynomial.
        """
        coefficients = problem
        computed_roots = np.roots(coefficients)
        sorted_roots = sorted(computed_roots, key=lambda z: (z.real, z.imag), reverse=True)
        return sorted_roots