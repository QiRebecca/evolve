from typing import Any

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solves the Minimum Dominating Set problem using a branch-and-bound
        algorithm with bitmask representation. This implementation is
        deterministic and returns an optimal solution.
        """
        n = len(problem)
        if n == 0:
            return []

        # Precompute cover bitmask for each node: node itself + its neighbors
        cover = [0] * n
        for i in range(n):
            mask = 1 << i
            for j in range(n):
                if problem[i][j]:
                    mask |= 1 << j
            cover[i] = mask

        all_ones = (1 << n) - 1

        # Greedy upper bound to initialize best solution
        def greedy_upper():
            dominated = 0
            chosen = 0
            while dominated != all_ones:
                # pick node that covers most uncovered nodes
                best_node = None
                best_cover = 0
                for v in range(n):
                    if (chosen >> v) & 1:
                        continue
                    new_cover = cover[v] & ~dominated
                    cnt = new_cover.bit_count()
                    if cnt > best_cover:
                        best_cover = cnt
                        best_node = v
                if best_node is None:
                    break
                chosen |= 1 << best_node
                dominated |= cover[best_node]
            return chosen

        best_mask = greedy_upper()
        best_size = best_mask.bit_count()

        # Precompute max cover size for lower bound
        max_cover_size = max(c.bit_count() for c in cover)

        # Recursive branch and bound
        def dfs(dominated_mask: int, chosen_mask: int, depth: int):
            nonlocal best_mask, best_size

            if dominated_mask == all_ones:
                if depth < best_size:
                    best_size = depth
                    best_mask = chosen_mask
                return

            # Prune if current depth already >= best
            if depth >= best_size:
                return

            # Lower bound estimate
            remaining = all_ones ^ dominated_mask
            remaining_bits = remaining.bit_count()
            lb = (remaining_bits + max_cover_size - 1) // max_cover_size
            if depth + lb >= best_size:
                return

            # Choose an uncovered node
            # Pick the node with smallest degree among uncovered to reduce branching
            # Find first uncovered node
            v = (remaining & -remaining).bit_length() - 1

            # Branch: include v
            dfs(dominated_mask | cover[v], chosen_mask | (1 << v), depth + 1)

            # Branch: include each neighbor of v (excluding v)
            neigh_mask = cover[v] & ~ (1 << v)
            # Iterate over set bits in neigh_mask
            m = neigh_mask
            while m:
                u = (m & -m).bit_length() - 1
                dfs(dominated_mask | cover[u], chosen_mask | (1 << u), depth + 1)
                m &= m - 1

        dfs(0, 0, 0)

        # Convert best_mask to list of indices
        result = [i for i in range(n) if (best_mask >> i) & 1]
        return result