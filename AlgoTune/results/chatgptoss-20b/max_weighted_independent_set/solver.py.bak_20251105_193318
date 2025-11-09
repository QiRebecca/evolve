from typing import Any
import logging

try:
    from ortools.sat.python import cp_model
except ImportError:
    cp_model = None

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solves the Maximum Weighted Independent Set (MWIS) problem.
        For graphs with up to 60 nodes, a branch-and-bound algorithm with
        bitmask representation is used for speed. For larger graphs,
        the CP-SAT solver from OR-Tools is employed as a fallback.
        """
        adj_matrix = problem["adj_matrix"]
        weights = problem["weights"]
        n = len(adj_matrix)

        # If graph is large, use CP-SAT baseline
        if n > 60 or cp_model is None:
            return self._solve_with_cp_sat(adj_matrix, weights)

        # Precompute adjacency masks
        adj_mask = [0] * n
        for i in range(n):
            mask = 1 << i
            for j in range(n):
                if adj_matrix[i][j]:
                    mask |= 1 << j
            adj_mask[i] = mask

        best_weight = 0
        best_set = []

        memo = {}

        def dfs(mask: int, current_weight: int, current_set: list):
            nonlocal best_weight, best_set

            if mask == 0:
                if current_weight > best_weight:
                    best_weight = current_weight
                    best_set = current_set.copy()
                return

            # Memoization prune
            if mask in memo and memo[mask] >= current_weight:
                return
            memo[mask] = current_weight

            # Upper bound: current weight + sum of remaining weights
            ub = current_weight
            m = mask
            while m:
                lsb = m & -m
                i = (lsb.bit_length() - 1)
                ub += weights[i]
                m -= lsb
            if ub <= best_weight:
                return

            # Choose node with maximum weight among remaining
            best_candidate = None
            best_candidate_weight = -1
            m = mask
            while m:
                lsb = m & -m
                i = (lsb.bit_length() - 1)
                w = weights[i]
                if w > best_candidate_weight:
                    best_candidate_weight = w
                    best_candidate = i
                m -= lsb

            # Branch: include candidate
            new_mask = mask & ~adj_mask[best_candidate]
            dfs(new_mask, current_weight + weights[best_candidate], current_set + [best_candidate])

            # Branch: exclude candidate
            mask_without = mask & ~(1 << best_candidate)
            dfs(mask_without, current_weight, current_set)

        full_mask = (1 << n) - 1
        dfs(full_mask, 0, [])

        return sorted(best_set)

    def _solve_with_cp_sat(self, adj_matrix, weights):
        n = len(adj_matrix)
        model = cp_model.CpModel()
        nodes = [model.NewBoolVar(f"x_{i}") for i in range(n)]

        for i in range(n):
            for j in range(i + 1, n):
                if adj_matrix[i][j]:
                    model.Add(nodes[i] + nodes[j] <= 1)

        model.Maximize(sum(weights[i] * nodes[i] for i in range(n)))

        solver = cp_model.CpSolver()
        status = solver.Solve(model)
        if status == cp_model.OPTIMAL or status == cp_model.FEASIBLE:
            return [i for i in range(n) if solver.Value(nodes[i])]
        else:
            logging.error("No solution found.")
            return []