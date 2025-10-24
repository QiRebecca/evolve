from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute all real roots of a polynomial with real coefficients.

        Parameters
        ----------
        problem : list[float]
            Polynomial coefficients in descending order [a_n, a_{n-1}, ..., a_0].

        Returns
        -------
        list[float]
            Real roots sorted in decreasing order.
        """
        coeffs = problem
        # Compute all roots (complex in general)
        roots = np.roots(coeffs)
        # Convert near‑real roots to real numbers
        roots = np.real_if_close(roots, tol=1e-3)
        roots = np.real(roots)
        # Sort in decreasing order
        roots = np.sort(roots)[::-1]
        return roots.tolist()