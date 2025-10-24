from typing import Any

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solves the maximum independent set problem using a bitset-based
        Bron–Kerbosch algorithm on the complement graph.
        """
        n = len(problem)
        if n == 0:
            return []

        # Build adjacency bitmask for the original graph
        adj = [0] * n
        for i in range(n):
            mask = 0
            row = problem[i]
            for j, val in enumerate(row):
                if val:
                    mask |= 1 << j
            adj[i] = mask

        # Build adjacency bitmask for the complement graph
        full_mask = (1 << n) - 1
        comp_adj = [0] * n
        for i in range(n):
            # neighbors in complement: all nodes except self and original neighbors
            comp_adj[i] = full_mask ^ (1 << i) ^ adj[i]

        best_size = 0
        best_set = 0

        # Precompute popcount for speed
        popcount = int.bit_count

        def bronk(R: int, P: int, X: int):
            nonlocal best_size, best_set
            if P == 0 and X == 0:
                size = popcount(R)
                if size > best_size:
                    best_size = size
                    best_set = R
                return
            # Upper bound pruning
            if popcount(R) + popcount(P) <= best_size:
                return

            # Choose pivot u from P|X with maximum degree in P
            ux = P | X
            # Find pivot with maximum intersection with P
            max_deg = -1
            pivot = -1
            temp = ux
            while temp:
                u = (temp & -temp).bit_length() - 1
                deg = popcount(P & comp_adj[u])
                if deg > max_deg:
                    max_deg = deg
                    pivot = u
                temp &= temp - 1

            # Candidates: vertices in P not adjacent to pivot
            candidates = P & ~comp_adj[pivot]
            while candidates:
                v = (candidates & -candidates).bit_length() - 1
                v_bit = 1 << v
                bronk(R | v_bit, P & comp_adj[v], X & comp_adj[v])
                P &= ~v_bit
                X |= v_bit
                candidates &= ~v_bit

        # Initial call
        bronk(0, full_mask, 0)

        # Convert best_set bitmask to list of indices
        result = []
        mask = best_set
        while mask:
            v = (mask & -mask).bit_length() - 1
            result.append(v)
            mask &= mask - 1
        return result