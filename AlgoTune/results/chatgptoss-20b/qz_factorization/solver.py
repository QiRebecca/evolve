from typing import Any
import numpy as np
from scipy.linalg import qz

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the QZ factorization of the matrix pair (A, B).
        Uses scipy.linalg.qz with output='real' to obtain real Schur form.
        """
        # Convert input lists to numpy arrays
        A = np.array(problem["A"])
        B = np.array(problem["B"])

        # Perform QZ factorization
        AA, BB, Q, Z = qz(A, B, output="real")

        # Prepare solution dictionary
        solution = {
            "QZ": {
                "AA": AA.tolist(),
                "BB": BB.tolist(),
                "Q": Q.tolist(),
                "Z": Z.tolist()
            }
        }
        return solution