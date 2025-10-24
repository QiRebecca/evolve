from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the L0 pruning problem: minimize ||v - w||^2 subject to ||w||_0 <= k.
        This implementation follows the baseline algorithm using a stable sort
        to select the k largest-magnitude entries of v.
        """
        v = np.array(problem.get("v"))
        k = problem.get("k")

        # Ensure v is a 1-D array
        v = v.flatten()

        pruned = np.zeros_like(v)
        # Stable sort by absolute value (ascending)
        indx = np.argsort(np.abs(v), kind="mergesort")
        # Take the last k indices (largest magnitudes)
        remaining_indx = indx[-k:]
        pruned[remaining_indx] = v[remaining_indx]

        return {"solution": pruned.tolist()}