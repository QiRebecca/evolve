from typing import Any
import numpy as np

class Solver:
    def __init__(self, mode: str = "full"):
        self.mode = mode

    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the 1D correlation for each valid pair in the problem list.

        For mode 'valid', process only pairs where the length of the second array does not exceed the first.
        Return a list of 1D arrays representing the correlation results.

        :param problem: A list of tuples of 1D arrays.
        :return: A list of 1D correlation results.
        """
        if "mode" in kwargs:
            self.mode = kwargs["mode"]

        results = []
        for a, b in problem:
            a_arr = np.asarray(a)
            b_arr = np.asarray(b)
            if self.mode == "valid" and b_arr.size > a_arr.size:
                continue
            res = np.correlate(a_arr, b_arr, mode=self.mode)
            results.append(res)
        return results