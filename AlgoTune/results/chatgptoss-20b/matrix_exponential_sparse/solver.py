from typing import Any
import scipy.sparse.linalg as splinalg
from scipy import sparse

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the matrix exponential of a sparse matrix using scipy's expm.
        Ensures the result is in CSC format.
        """
        A = problem["matrix"]
        solution = splinalg.expm(A)
        if not sparse.isspmatrix_csc(solution):
            solution = solution.tocsc()
        return solution