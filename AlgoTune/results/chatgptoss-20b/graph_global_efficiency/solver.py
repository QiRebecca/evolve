from typing import Any
from collections import deque

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Calculate the global efficiency of an undirected graph given its adjacency list.
        This implementation uses BFS from each node to compute shortest path lengths,
        avoiding the overhead of NetworkX and providing faster execution for large graphs.
        """
        adj_list = problem.get("adjacency_list", [])
        n = len(adj_list)

        # Edge cases: 0 or 1 node -> efficiency 0
        if n <= 1:
            return {"global_efficiency": 0.0}

        total_pairs = n * (n - 1)
        sum_inv_dist = 0.0

        # For each source node, perform BFS
        for src in range(n):
            # distances initialized to -1 (unvisited)
            dist = [-1] * n
            dist[src] = 0
            q = deque([src])

            while q:
                u = q.popleft()
                du = dist[u]
                for v in adj_list[u]:
                    if dist[v] == -1:
                        dist[v] = du + 1
                        q.append(v)

            # Accumulate contributions for pairs (src, v) where v > src
            for dst in range(src + 1, n):
                d = dist[dst]
                if d > 0:  # reachable and not same node
                    sum_inv_dist += 1.0 / d

        efficiency = sum_inv_dist / total_pairs
        return {"global_efficiency": float(efficiency)}