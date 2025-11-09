from typing import Any
import networkx as nx
from networkx.algorithms.clique import max_clique

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Find the maximum common induced subgraph between two undirected graphs
        represented by adjacency matrices A and B. The solution is a list of
        tuples (i, p) indicating that node i in graph G is mapped to node p in
        graph H. The mapping is one-to-one and preserves adjacency.
        """
        A = problem.get("A", [])
        B = problem.get("B", [])
        n = len(A)
        m = len(B)

        # If either graph is empty, no mapping exists
        if n == 0 or m == 0:
            return []

        # Build the product graph where vertices are pairs (i, p)
        # and edges exist only between pairs with distinct i, distinct p
        # and matching adjacency in A and B.
        Gp = nx.Graph()
        # Add all possible pairs as nodes
        for i in range(n):
            for p in range(m):
                Gp.add_node((i, p))

        # Add edges between compatible pairs
        for i in range(n):
            for j in range(i + 1, n):
                a_ij = A[i][j]
                for p in range(m):
                    for q in range(p + 1, m):
                        if a_ij == B[p][q]:
                            Gp.add_edge((i, p), (j, q))

        # Find a maximum clique in the product graph
        # This clique corresponds to the maximum common subgraph.
        try:
            clique = max_clique(Gp)
        except Exception:
            # Fallback: if max_clique fails, return empty mapping
            return []

        # Convert clique nodes back to mapping pairs
        mapping = [(i, p) for (i, p) in clique]
        # Sort by G node index for deterministic output
        mapping.sort(key=lambda x: x[0])
        return mapping