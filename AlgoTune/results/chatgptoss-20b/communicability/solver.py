from typing import Any
import numpy as np
from scipy.linalg import expm

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Calculates the communicability matrix for an undirected graph
        represented by an adjacency list. The communicability is defined
        as the matrix exponential of the adjacency matrix.

        Parameters
        ----------
        problem : dict
            Dictionary containing the key "adjacency_list" with the
            adjacency list representation of the graph.

        Returns
        -------
        dict
            Dictionary with a single key "communicability" whose value
            is a nested dictionary mapping node indices to dictionaries
            of communicability values with all other nodes.
        """
        adj_list = problem.get("adjacency_list", [])
        n = len(adj_list)

        # Handle empty graph
        if n == 0:
            return {"communicability": {}}

        # Build adjacency matrix
        A = np.zeros((n, n), dtype=float)
        for u, neighbors in enumerate(adj_list):
            for v in neighbors:
                A[u, v] = 1.0
                A[v, u] = 1.0  # ensure symmetry

        # Compute matrix exponential
        expA = expm(A)

        # Convert to nested dict with int keys and float values
        communicability = {
            u: {v: float(expA[u, v]) for v in range(n)}
            for u in range(n)
        }

        return {"communicability": communicability}