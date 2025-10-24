from typing import Any
import sys

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Find articulation points in an undirected graph using Tarjan's algorithm.
        """
        sys.setrecursionlimit(10 ** 6)

        n = problem["num_nodes"]
        edges = problem["edges"]

        # Build adjacency list
        adj = [[] for _ in range(n)]
        for u, v in edges:
            adj[u].append(v)
            adj[v].append(u)

        disc = [-1] * n
        low = [0] * n
        parent = [-1] * n
        ap = [False] * n
        time = 0

        def dfs(u: int):
            nonlocal time
            disc[u] = low[u] = time
            time += 1
            children = 0

            for v in adj[u]:
                if disc[v] == -1:  # Tree edge
                    parent[v] = u
                    children += 1
                    dfs(v)
                    low[u] = min(low[u], low[v])

                    if parent[u] == -1 and children > 1:
                        ap[u] = True
                    if parent[u] != -1 and low[v] >= disc[u]:
                        ap[u] = True
                elif v != parent[u]:  # Back edge
                    low[u] = min(low[u], disc[v])

        for i in range(n):
            if disc[i] == -1:
                dfs(i)

        articulation_points = [i for i, is_ap in enumerate(ap) if is_ap]
        articulation_points.sort()
        return {"articulation_points": articulation_points}