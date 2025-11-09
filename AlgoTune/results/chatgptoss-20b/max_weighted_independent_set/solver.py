from typing import Any
import sys

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solves the Maximum Weighted Independent Set problem using a branch and bound
        algorithm with bitset representation. This implementation is typically faster
        than the CP-SAT baseline for small to medium sized graphs.
        """
        adj_matrix = problem["adj_matrix"]
        weights = problem["weights"]
        n = len(weights)

        # Build adjacency bitmask for each node (including the node itself)
        adj_mask = [0] * n
        for i in range(n):
            mask = 1 << i
            row = adj_matrix[i]
            for j, val in enumerate(row):
                if val:
                    mask |= 1 << j
            adj_mask[i] = mask

        # Greedy initial solution to provide a lower bound
        order = sorted(range(n), key=lambda i: -weights[i])
        chosen = []
        used = 0
        for i in order:
            if not (used & (1 << i)):
                chosen.append(i)
                used |= adj_mask[i]
        best_weight = sum(weights[i] for i in chosen)
        best_set = chosen

        # Branch and bound
        sys.setrecursionlimit(10000)
        best_weight_ref = [best_weight]
        best_set_ref = [best_set]

        full_mask = (1 << n) - 1
        total_weight = sum(weights)

        def dfs(mask: int, current_weight: int, current_set: list, remaining_weight: int):
            # Prune if even taking all remaining nodes cannot beat best
            if current_weight + remaining_weight <= best_weight_ref[0]:
                return
            if mask == 0:
                if current_weight > best_weight_ref[0]:
                    best_weight_ref[0] = current_weight
                    best_set_ref[0] = current_set.copy()
                return

            # Choose a node with maximum weight in the current mask
            max_w = -1
            node = None
            m = mask
            while m:
                lsb = m & -m
                i = (lsb.bit_length() - 1)
                if weights[i] > max_w:
                    max_w = weights[i]
                    node = i
                m -= lsb

            # Include the chosen node
            neighbor_mask = adj_mask[node] & mask
            new_mask = mask & ~neighbor_mask
            # Sum weights of nodes removed (node + its neighbors)
            sum_removed = 0
            mm = neighbor_mask
            while mm:
                lsb = mm & -mm
                j = (lsb.bit_length() - 1)
                sum_removed += weights[j]
                mm -= lsb
            new_remaining_weight = remaining_weight - sum_removed
            current_set.append(node)
            dfs(new_mask, current_weight + weights[node], current_set, new_remaining_weight)
            current_set.pop()

            # Exclude the chosen node
            mask_without_node = mask & ~(1 << node)
            remaining_weight_excl = remaining_weight - weights[node]
            dfs(mask_without_node, current_weight, current_set, remaining_weight_excl)

        dfs(full_mask, 0, [], total_weight)
        return sorted(best_set_ref[0])