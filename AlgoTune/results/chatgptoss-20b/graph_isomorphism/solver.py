from typing import Any

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Find an isomorphism mapping between two isomorphic undirected graphs.
        The algorithm uses a simple backtracking search with degree-based pruning.
        """
        n = problem["num_nodes"]
        edges_g1 = problem["edges_g1"]
        edges_g2 = problem["edges_g2"]

        # Build adjacency sets for both graphs
        adj1 = [set() for _ in range(n)]
        adj2 = [set() for _ in range(n)]
        for u, v in edges_g1:
            adj1[u].add(v)
            adj1[v].add(u)
        for x, y in edges_g2:
            adj2[x].add(y)
            adj2[y].add(x)

        # Degrees
        deg1 = [len(adj1[i]) for i in range(n)]
        deg2 = [len(adj2[i]) for i in range(n)]

        # Candidate lists: nodes in G2 with the same degree as each node in G1
        candidates = [[] for _ in range(n)]
        for u in range(n):
            du = deg1[u]
            for v in range(n):
                if du == deg2[v]:
                    candidates[u].append(v)

        # Order nodes by increasing number of candidates to reduce branching
        order = sorted(range(n), key=lambda u: len(candidates[u]))

        mapping = [-1] * n
        used = [False] * n

        # Recursive backtracking search
        def dfs(idx: int) -> bool:
            if idx == n:
                return True
            u = order[idx]
            for v in candidates[u]:
                if used[v]:
                    continue

                # Check consistency with already mapped neighbors
                ok = True
                for w in adj1[u]:
                    mw = mapping[w]
                    if mw != -1 and mw not in adj2[v]:
                        ok = False
                        break
                if not ok:
                    continue
                for w in adj2[v]:
                    mw = mapping[w]
                    if mw != -1 and w not in adj1[u]:
                        ok = False
                        break
                if not ok:
                    continue

                mapping[u] = v
                used[v] = True
                if dfs(idx + 1):
                    return True
                mapping[u] = -1
                used[v] = False
            return False

        # Start the search
        dfs(0)

        return {"mapping": mapping}