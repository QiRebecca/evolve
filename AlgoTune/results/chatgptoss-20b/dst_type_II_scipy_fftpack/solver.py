from typing import Any
import numpy as np
from scipy.fft import dstn

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the N-dimensional DST Type II using scipy.fft.dstn.
        """
        # Ensure input is a NumPy array
        arr = np.asarray(problem)
        # Compute DST Type II
        result = dstn(arr, type=2)
        return result