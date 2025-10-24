from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute eigenvalues of a real square matrix and return them sorted
        in descending order by real part, then by imaginary part.
        """
        # Compute eigenvalues efficiently
        vals = np.linalg.eigvals(problem)
        # Sort descending by real part, then by imaginary part
        # Use lexsort on negative values for descending order
        indices = np.lexsort((-vals.imag, -vals.real))
        sorted_vals = vals[indices]
        # Convert to list of complex numbers
        return [complex(v) for v in sorted_vals]