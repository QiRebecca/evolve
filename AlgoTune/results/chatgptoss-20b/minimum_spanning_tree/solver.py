from typing import Any

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the Minimum Spanning Tree (MST) of an undirected weighted graph
        using Kruskal's algorithm with deterministic tie-breaking to match
        networkx's default behavior.

        :param problem: dict with 'num_nodes' and 'edges' keys
        :return: dict with 'mst_edges' key containing the MST edges
        """
        num_nodes = problem["num_nodes"]
        edges_input = problem["edges"]

        # Prepare edges with deterministic ordering: (weight, min(u,v), max(u,v))
        edges = []
        for u, v, w in edges_input:
            u_min, v_max = (u, v) if u <= v else (v, u)
            edges.append((w, u_min, v_max, u, v))

        # Sort edges by weight, then by node order to match networkx's tie-breaking
        edges.sort(key=lambda x: (x[0], x[1], x[2]))

        # Union-Find data structures
        parent = list(range(num_nodes))
        rank = [0] * num_nodes

        def find(x: int) -> int:
            while parent[x] != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x

        def union(x: int, y: int) -> bool:
            rx, ry = find(x), find(y)
            if rx == ry:
                return False
            if rank[rx] < rank[ry]:
                parent[rx] = ry
            elif rank[rx] > rank[ry]:
                parent[ry] = rx
            else:
                parent[ry] = rx
                rank[rx] += 1
            return True

        mst_edges = []
        for w, u_min, v_max, u_orig, v_orig in edges:
            if union(u_orig, v_orig):
                mst_edges.append([u_min, v_max, w])

        # Sort the resulting MST edges by (u, v) for consistency
        mst_edges.sort(key=lambda x: (x[0], x[1]))

        return {"mst_edges": mst_edges}