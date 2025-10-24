from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the N-dimensional FFT using numpy's FFT implementation.
        """
        return np.fft.fftn(problem)