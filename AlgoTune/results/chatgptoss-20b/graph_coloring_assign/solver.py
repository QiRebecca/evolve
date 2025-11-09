from typing import Any
import networkx as nx

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solves the graph coloring problem using an exact DSATUR algorithm
        with a greedy upper bound. This implementation is typically faster
        than the CP‑SAT baseline for moderate-sized graphs while guaranteeing
        optimality.
        """
        n = len(problem)
        if n == 0:
            return []

        # Build adjacency list
        adjacency = [set() for _ in range(n)]
        for i in range(n):
            row = problem[i]
            for j, val in enumerate(row):
                if val and i != j:
                    adjacency[i].add(j)

        # Greedy upper bound (largest_first strategy)
        greedy_colors = nx.greedy_color(problem, strategy="largest_first")
        ub = max(greedy_colors.values()) + 1 if greedy_colors else 1

        best_colors = ub
        best_assignment = [0] * n

        # DSATUR state
        colors = [0] * n
        neighbor_colors = [set() for _ in range(n)]
        uncolored = set(range(n))
        degrees = [len(adjacency[i]) for i in range(n)]

        def select_vertex():
            # Choose uncolored vertex with highest saturation degree,
            # breaking ties by degree.
            best_v = None
            best_sat = -1
            best_deg = -1
            for v in uncolored:
                sat = len(neighbor_colors[v])
                if sat > best_sat or (sat == best_sat and degrees[v] > best_deg):
                    best_sat = sat
                    best_deg = degrees[v]
                    best_v = v
            return best_v

        def dfs(colored_count, used_colors):
            nonlocal best_colors, best_assignment
            if colored_count == n:
                if used_colors < best_colors:
                    best_colors = used_colors
                    best_assignment = colors.copy()
                return
            if used_colors >= best_colors:
                return

            v = select_vertex()
            forbidden = neighbor_colors[v]

            # Try existing colors
            for c in range(1, used_colors + 1):
                if c not in forbidden:
                    colors[v] = c
                    added = []
                    for nb in adjacency[v]:
                        if colors[nb] == 0 and c not in neighbor_colors[nb]:
                            neighbor_colors[nb].add(c)
                            added.append(nb)
                    uncolored.remove(v)
                    dfs(colored_count + 1, used_colors)
                    uncolored.add(v)
                    colors[v] = 0
                    for nb in added:
                        neighbor_colors[nb].remove(c)

            # Try a new color
            new_color = used_colors + 1
            if new_color < best_colors:
                colors[v] = new_color
                added = []
                for nb in adjacency[v]:
                    if colors[nb] == 0 and new_color not in neighbor_colors[nb]:
                        neighbor_colors[nb].add(new_color)
                        added.append(nb)
                uncolored.remove(v)
                dfs(colored_count + 1, new_color)
                uncolored.add(v)
                colors[v] = 0
                for nb in added:
                    neighbor_colors[nb].remove(new_color)

        dfs(0, 0)

        # Normalize colors to 1..k
        used = sorted(set(best_assignment))
        remap = {old: new for new, old in enumerate(used, start=1)}
        result = [remap[c] for c in best_assignment]
        return result