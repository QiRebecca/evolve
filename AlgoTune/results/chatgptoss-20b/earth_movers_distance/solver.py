from typing import Any
import numpy as np
import ot

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the Earth Mover's Distance (optimal transport) problem.

        Parameters
        ----------
        problem : dict
            Dictionary containing:
                - "source_weights": list or array of source distribution weights.
                - "target_weights": list or array of target distribution weights.
                - "cost_matrix": 2D array-like cost matrix.

        Returns
        -------
        dict
            Dictionary with key "transport_plan" containing the optimal transport plan matrix.
        """
        # Extract and convert inputs to numpy arrays
        a = np.asarray(problem["source_weights"], dtype=np.float64)
        b = np.asarray(problem["target_weights"], dtype=np.float64)
        M = np.asarray(problem["cost_matrix"], dtype=np.float64)

        # Ensure cost matrix is C-contiguous as required by ot.lp.emd
        M_cont = np.ascontiguousarray(M, dtype=np.float64)

        # Compute the optimal transport plan using POT's linear programming solver
        G = ot.lp.emd(a, b, M_cont, check_marginals=False)

        return {"transport_plan": G}