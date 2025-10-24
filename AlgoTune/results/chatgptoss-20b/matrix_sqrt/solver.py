from typing import Any
import numpy as np
import scipy.linalg
import logging

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Computes the principal matrix square root of a square matrix A.

        Parameters
        ----------
        problem : dict
            Dictionary containing the key 'matrix' with a numpy.ndarray of shape (n, n).

        Returns
        -------
        dict
            Dictionary with key 'sqrtm' mapping to a dictionary containing the key 'X',
            which is a list of lists of complex numbers representing the principal square root.
        """
        A = problem.get("matrix")
        if A is None:
            logging.error("Problem does not contain 'matrix'.")
            return {"sqrtm": {"X": []}}

        try:
            X, _ = scipy.linalg.sqrtm(A, disp=False)
        except Exception as e:
            logging.error(f"scipy.linalg.sqrtm failed: {e}")
            return {"sqrtm": {"X": []}}

        return {"sqrtm": {"X": X.tolist()}}