from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the QR factorization of the input matrix A using NumPy's
        linalg.qr function with mode='reduced'.
        """
        A = problem["matrix"]
        Q, R = np.linalg.qr(A, mode="reduced")
        return {"QR": {"Q": Q.tolist(), "R": R.tolist()}}