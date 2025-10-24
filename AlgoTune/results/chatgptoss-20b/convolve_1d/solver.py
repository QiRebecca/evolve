from typing import Any
import numpy as np

class Solver:
    def __init__(self, mode: str = "full"):
        self.mode = mode

    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the 1D correlation (linear convolution) of two input arrays.

        Parameters
        ----------
        problem : tuple
            A tuple containing two 1D sequences (a, b).
        **kwargs : dict
            Optional keyword arguments. If 'mode' is provided, it overrides
            the instance's default mode.

        Returns
        -------
        np.ndarray
            The convolution result as a 1D NumPy array.
        """
        a, b = problem
        mode = kwargs.get("mode", self.mode)
        return np.convolve(a, b, mode=mode)