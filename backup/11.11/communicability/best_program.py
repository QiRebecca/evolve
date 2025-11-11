import math
from typing import Any, Dict

import numpy as np
from scipy.linalg import expm


class Solver:
    def solve(self, problem: Dict[str, Any], **kwargs) -> Dict[str, Dict[int, Dict[int, float]]]:
        """
        Compute communicability C(u, v) for every pair of nodes in an undirected graph:
            C(u, v) = (e^A)_{uv}
        where A is the adjacency matrix.

        The input `problem` contains:
            {"adjacency_list": [[neighbors of node 0], [neighbors of node 1], …]}

        The output format is:
            {"communicability": {u: {v: float, ...}, ...}}
        """
        adj_list = problem["adjacency_list"]
        n = len(adj_list)

        # Empty graph → empty communicability dictionary
        if n == 0:
            return {"communicability": {}}

        # ------------------------------------------------------------------
        # 1. Build the (dense) adjacency matrix quickly with NumPy.
        # ------------------------------------------------------------------
        A = np.zeros((n, n), dtype=float)
        # Collect edges in two flat index lists to avoid Python loops inside NumPy.
        row_idx = []
        col_idx = []
        for u, nbrs in enumerate(adj_list):
            if nbrs:                       # skip empty lists to avoid tiny overhead
                row_idx.extend([u] * len(nbrs))
                col_idx.extend(nbrs)

        if row_idx:                       # Non-empty edge set
            A[row_idx, col_idx] = 1.0
            # Undirected graph: mirror the upper-triangle assignments.
            A[col_idx, row_idx] = 1.0

        # ------------------------------------------------------------------
        # 2. Matrix exponential (SciPy is BLAS/LAPACK-accelerated and fast).
        # ------------------------------------------------------------------
        expA = expm(A)   # shape (n, n), dtype=float64

        # ------------------------------------------------------------------
        # 3. Convert to the required nested-dict structure using
        #    fast NumPy iteration and minimal Python overhead.
        # ------------------------------------------------------------------
        # Pre-allocate outer dictionary with integer keys for determinism.
        communicability: Dict[int, Dict[int, float]] = {u: {} for u in range(n)}

        # Using .tolist() is faster than repeated expA[i, j] Python calls.
        expA_list = expA.tolist()
        for u in range(n):
            row = expA_list[u]
            inner = communicability[u]
            # Convert every value in the row to plain Python float.
            inner.update({v: float(row[v]) for v in range(n)})

        return {"communicability": communicability}