from typing import Any
import networkx as nx
from ortools.sat.python import cp_model

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solves the graph coloring problem using a compact CP‑SAT formulation.
        The model uses integer variables for vertex colors and a single variable
        K for the maximum color used.  This approach is typically faster than
        the binary matrix formulation used in the baseline.
        """
        n = len(problem)
        if n == 0:
            return []

        # Build graph
        G = nx.Graph()
        G.add_nodes_from(range(n))
        for i in range(n):
            for j in range(i + 1, n):
                if problem[i][j]:
                    G.add_edge(i, j)

        # Upper bound via greedy coloring
        greedy = nx.greedy_color(G, strategy="largest_first")
        ub = max(greedy.values()) + 1  # colors are 0-indexed

        # Lower bound via maximum clique (approximate for speed)
        try:
            # Exact maximum clique (may be slow for very large graphs)
            max_clique_size = max(len(c) for c in nx.find_cliques(G))
        except Exception:
            # Fallback to approximation
            max_clique_size = len(nx.algorithms.approximation.clique.max_clique(G))
        lb = max_clique_size

        # If lower bound equals upper bound, greedy is optimal
        if lb == ub:
            return [c + 1 for c in greedy]

        # CP‑SAT model
        model = cp_model.CpModel()

        # Color variables for each vertex (1..ub)
        color = {}
        for v in range(n):
            color[v] = model.NewIntVar(1, ub, f"c_{v}")

        # K variable: maximum color used
        K = model.NewIntVar(1, ub, "K")

        # Each color <= K
        for v in range(n):
            model.Add(color[v] <= K)

        # Adjacent vertices must have different colors
        for u, v in G.edges():
            model.Add(color[u] != color[v])

        # Objective: minimize K
        model.Minimize(K)

        # Solve
        solver = cp_model.CpSolver()
        solver.parameters.max_time_in_seconds = 60.0  # safety limit
        status = solver.Solve(model)

        if status not in (cp_model.OPTIMAL, cp_model.FEASIBLE):
            return []

        # Extract colors
        colors = [solver.Value(color[v]) for v in range(n)]

        # Normalize colors to 1..k
        used = sorted(set(colors))
        remap = {old: new for new, old in enumerate(used, start=1)}
        colors = [remap[c] for c in colors]

        return colors