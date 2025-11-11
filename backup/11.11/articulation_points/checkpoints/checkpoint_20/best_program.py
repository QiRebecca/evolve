from typing import Any, List, Sequence
import sys


class Solver:
    """
    Fast articulation-point finder for an undirected graph using Tarjan's DFS
    (low-link) algorithm.  Runs in O(V+E) time and avoids NetworkX overhead.
    """

    __slots__ = ()

    def solve(self, problem: dict[str, Any], **kwargs) -> dict[str, List[int]]:
        # Extract data with safe defaults
        n: int = int(problem.get("num_nodes", 0))
        raw_edges: Sequence = problem.get("edges", ())

        # Convert to a list when the container is not already a list.
        # This also resolves NumPy ndarray inputs whose truthiness is ambiguous.
        if not isinstance(raw_edges, list):
            # ndarray has .tolist(), fall back to list() otherwise
            raw_edges = raw_edges.tolist() if hasattr(raw_edges, "tolist") else list(raw_edges)

        m = len(raw_edges)

        # Trivial graphs (≤2 vertices or no edges) have no articulation points
        if n <= 2 or m == 0:
            return {"articulation_points": []}

        # Build adjacency list
        adj: List[List[int]] = [[] for _ in range(n)]
        for e in raw_edges:
            # Support edge given as list/tuple/ndarray
            u, v = int(e[0]), int(e[1])
            adj[u].append(v)
            adj[v].append(u)

        # Increase recursion limit for deep DFS traversals
        sys.setrecursionlimit(max(1_000_000, n * 4 + 100))

        disc = [-1] * n        # discovery times
        low = [0] * n          # low-link values
        parent = [-1] * n      # parent in DFS tree
        is_ap = [False] * n    # articulation point flags
        timer = 0              # global timestamp

        def dfs(u: int) -> None:
            nonlocal timer
            disc[u] = low[u] = timer
            timer += 1
            children = 0

            for v in adj[u]:
                if disc[v] == -1:          # Tree edge
                    parent[v] = u
                    children += 1
                    dfs(v)

                    # Update low value of u based on child's low
                    if low[v] < low[u]:
                        low[u] = low[v]

                    # Articulation conditions
                    if parent[u] == -1:
                        if children > 1:
                            is_ap[u] = True
                    elif low[v] >= disc[u]:
                        is_ap[u] = True
                elif v != parent[u]:       # Back edge
                    if disc[v] < low[u]:
                        low[u] = disc[v]

        # Run DFS for every component
        for v in range(n):
            if disc[v] == -1:
                dfs(v)

        articulation_points = [i for i, flag in enumerate(is_ap) if flag]
        articulation_points.sort()
        return {"articulation_points": articulation_points}