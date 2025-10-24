from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute PageRank scores for a directed graph given its adjacency list.
        This implementation uses a custom power iteration algorithm that
        avoids the overhead of NetworkX and is optimized for speed.

        Parameters
        ----------
        problem : dict
            Dictionary containing the key "adjacency_list" with a list of
            lists of outgoing neighbors for each node.
        **kwargs : dict
            Optional parameters:
                alpha : float, damping factor (default 0.85)
                max_iter : int, maximum number of iterations (default 100)
                tol : float, convergence tolerance (default 1e-06)

        Returns
        -------
        dict
            Dictionary with key "pagerank_scores" mapping to a list of
            PageRank scores in node index order.
        """
        adj_list = problem.get("adjacency_list", [])
        n = len(adj_list)

        # Handle trivial cases
        if n == 0:
            return {"pagerank_scores": []}
        if n == 1:
            return {"pagerank_scores": [1.0]}

        # Parameters
        alpha = kwargs.get("alpha", 0.85)
        max_iter = kwargs.get("max_iter", 100)
        tol = kwargs.get("tol", 1e-06)

        # Precompute out-degree and dangling node mask
        out_deg = np.array([len(neigh) for neigh in adj_list], dtype=np.int32)
        dangling_mask = out_deg == 0

        # Initialize PageRank vector uniformly
        r = np.full(n, 1.0 / n, dtype=np.float64)

        # Preallocate array for new ranks
        new_r = np.empty(n, dtype=np.float64)

        for _ in range(max_iter):
            # Start with teleportation component
            new_r.fill((1.0 - alpha) / n)

            # Handle dangling nodes: distribute their rank uniformly
            if np.any(dangling_mask):
                dangling_sum = r[dangling_mask].sum()
                new_r += alpha * dangling_sum / n

            # Distribute rank from non-dangling nodes
            for i, neighbors in enumerate(adj_list):
                if out_deg[i] == 0:
                    continue
                share = alpha * r[i] / out_deg[i]
                new_r[neighbors] += share

            # Check convergence
            diff = np.abs(new_r - r).sum()
            if diff < tol:
                r = new_r
                break

            r, new_r = new_r, r  # swap references for next iteration

        # Ensure the result sums to 1.0 (normalization)
        r /= r.sum()

        return {"pagerank_scores": r.tolist()}