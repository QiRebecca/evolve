from typing import Any, Iterable, Tuple, Dict, List, Set

import pulp
import networkx as nx


class Solver:
    def solve(self, problem: Tuple[Dict[str, Dict[str, float]], int], **kwargs) -> Any:
        """
        Solves the k-centers problem for the given graph instance.

        The function computes all-pairs shortest path distances, then uses a binary
        search over the sorted unique distances. For each candidate radius it
        solves a feasibility integer program that asks whether there exists a
        set of at most k centers covering all nodes within that radius.

        Args:
            problem: A tuple (G, k) where G is the weighted graph dictionary and k is the number of centers.

        Returns:
            List of node IDs chosen as centers.
        """
        G_dict, k = problem

        # Handle trivial cases
        if not G_dict:
            return []

        if k == 0:
            return []

        # Build a networkx graph
        graph = nx.Graph()
        for v, adj in G_dict.items():
            for w, d in adj.items():
                graph.add_edge(v, w, weight=d)

        # Compute all-pairs shortest path lengths
        all_dist = dict(nx.all_pairs_dijkstra_path_length(graph, weight="weight"))

        # Gather all unique distances
        unique_distances: Set[float] = set()
        for src, dists in all_dist.items():
            unique_distances.update(dists.values())
        sorted_distances = sorted(unique_distances)

        # Helper to check feasibility for a given radius
        def feasible(radius: float) -> Tuple[bool, List[str]]:
            prob = pulp.LpProblem("k_center", pulp.LpMinimize)
            # Binary variable for each node: 1 if chosen as center
            x = {v: pulp.LpVariable(f"x_{v}", cat="Binary") for v in graph.nodes}

            # Objective: minimize number of centers (not needed but helps solver)
            prob += pulp.lpSum(x[v] for v in graph.nodes)

            # Constraint: at most k centers
            prob += pulp.lpSum(x[v] for v in graph.nodes) <= k

            # Coverage constraints: each node must be within radius of some center
            for u in graph.nodes:
                covering_nodes = [v for v in graph.nodes if all_dist[u][v] <= radius]
                prob += pulp.lpSum(x[v] for v in covering_nodes) >= 1

            # Solve
            prob.solve(pulp.PULP_CBC_CMD(msg=0))
            if pulp.LpStatus[prob.status] == "Optimal" or pulp.LpStatus[prob.status] == "Feasible":
                centers = [v for v in graph.nodes if pulp.value(x[v]) > 0.5]
                return True, centers
            return False, []

        # Binary search for minimal radius
        lo, hi = 0, len(sorted_distances) - 1
        best_radius = sorted_distances[hi]
        best_centers: List[str] = []

        while lo <= hi:
            mid = (lo + hi) // 2
            radius = sorted_distances[mid]
            ok, centers = feasible(radius)
            if ok:
                best_radius = radius
                best_centers = centers
                hi = mid - 1
            else:
                lo = mid + 1

        return best_centers