from typing import Any

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Calculates the edge expansion for the given subset S in the graph.
        This implementation avoids external libraries for speed.
        """
        adj_list = problem.get("adjacency_list", [])
        nodes_S_list = problem.get("nodes_S", [])
        n = len(adj_list)
        nodes_S = set(nodes_S_list)

        # Edge cases: empty graph, empty S, or S contains all nodes
        if n == 0 or not nodes_S or len(nodes_S) == n:
            return {"edge_expansion": 0.0}

        # Count edges from S to V \ S
        out_edges = 0
        for u in nodes_S:
            for v in adj_list[u]:
                if v not in nodes_S:
                    out_edges += 1

        expansion = float(out_edges) / len(nodes_S)
        return {"edge_expansion": expansion}