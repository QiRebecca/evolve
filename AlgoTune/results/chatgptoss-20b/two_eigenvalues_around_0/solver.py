from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Find the two eigenvalues of a symmetric matrix that are closest to zero.
        Uses efficient partial selection to avoid full sorting of all eigenvalues.
        """
        # Convert input to NumPy array
        matrix = np.array(problem["matrix"], dtype=float)

        # Compute all eigenvalues (sorted ascending by value)
        eigs = np.linalg.eigvalsh(matrix)

        # Find indices of the two eigenvalues with smallest absolute value
        # np.argpartition gives unsorted indices of the k smallest elements
        idx = np.argpartition(np.abs(eigs), 2)[:2]

        # Retrieve the selected eigenvalues
        selected = eigs[idx]

        # Sort the two selected eigenvalues by absolute value
        selected_sorted = sorted(selected, key=abs)

        return selected_sorted