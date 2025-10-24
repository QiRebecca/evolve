from typing import Any
import numpy as np
import scipy.sparse
import logging

class Solver:
    def __init__(self):
        # Default parameters for shortest_path
        self.method = 'D'  # Dijkstra
        self.directed = False

    def solve(self, problem, **kwargs) -> Any:
        """
        Compute all-pairs shortest path distances for an undirected weighted sparse graph
        represented in CSR format.

        Parameters
        ----------
        problem : dict
            Dictionary containing CSR components:
                - "data": list of edge weights
                - "indices": list of column indices
                - "indptr": list of index pointers
                - "shape": [n, n] number of nodes
        kwargs : dict
            Optional overrides for 'method' and 'directed'.

        Returns
        -------
        dict
            {"distance_matrix": list of lists with None for unreachable pairs}
        """
        # Update parameters if provided
        self.method = kwargs.get('method', self.method)
        self.directed = kwargs.get('directed', self.directed)

        # Reconstruct CSR matrix
        try:
            graph_csr = scipy.sparse.csr_matrix(
                (problem["data"], problem["indices"], problem["indptr"]),
                shape=problem["shape"]
            )
        except Exception as e:
            logging.error(f"Failed to reconstruct CSR matrix: {e}")
            return {"distance_matrix": []}

        # Compute all-pairs shortest paths
        try:
            dist_matrix = scipy.sparse.csgraph.shortest_path(
                csgraph=graph_csr,
                method=self.method,
                directed=self.directed
            )
        except Exception as e:
            logging.error(f"scipy.sparse.csgraph.shortest_path failed: {e}")
            return {"distance_matrix": []}

        # Convert to list of lists, replacing np.inf with None
        try:
            # Use list comprehension for speed
            distance_matrix = [
                [None if np.isinf(x) else float(x) for x in row]
                for row in dist_matrix.tolist()
            ]
        except Exception as e:
            logging.error(f"Failed to convert distance matrix to list: {e}")
            return {"distance_matrix": []}

        return {"distance_matrix": distance_matrix}