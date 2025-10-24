from typing import Any
import numpy as np
from scipy.linalg import expm

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the matrix exponential of a square matrix A.

        Parameters
        ----------
        problem : dict
            Dictionary containing the key "matrix" with a 2D list or numpy array.

        Returns
        -------
        dict
            Dictionary with key "exponential" containing the matrix exponential
            as a list of lists.
        """
        # Extract matrix and ensure it is a NumPy array
        A = np.asarray(problem["matrix"])
        # Compute the matrix exponential using SciPy
        expA = expm(A)
        # Convert result to a nested Python list for JSON serialisation
        return {"exponential": expA.tolist()}