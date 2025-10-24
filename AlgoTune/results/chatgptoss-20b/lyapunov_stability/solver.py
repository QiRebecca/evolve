from typing import Any
import numpy as np
from scipy.linalg import solve_discrete_lyapunov

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Determines asymptotic stability of a discrete-time LTI system
        and returns a Lyapunov matrix P if stable.

        Parameters
        ----------
        problem : dict
            Dictionary containing the system matrix A under key "A".

        Returns
        -------
        dict
            {"is_stable": bool, "P": list[list[float]] or None}
        """
        A = np.array(problem["A"])
        # Check eigenvalues for stability
        eigvals = np.linalg.eigvals(A)
        if np.any(np.abs(eigvals) >= 1):
            return {"is_stable": False, "P": None}

        # Solve discrete Lyapunov equation A^T P A - P = -I
        try:
            P = solve_discrete_lyapunov(A.T, np.eye(A.shape[0]))
        except Exception:
            return {"is_stable": False, "P": None}

        # Ensure symmetry (numerical errors)
        P = (P + P.T) / 2.0

        # Convert to list of lists
        P_list = P.tolist()
        return {"is_stable": True, "P": P_list}