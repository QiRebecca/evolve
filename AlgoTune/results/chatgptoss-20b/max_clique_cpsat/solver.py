from typing import Any

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solves the maximum clique problem using a Bron–Kerbosch algorithm with pivoting.
        Returns a list of node indices that form a maximum clique.
        """
        n = len(problem)
        if n == 0:
            return []

        # Build adjacency bitsets
        adj = [0] * n
        for i in range(n):
            mask = 0
            row = problem[i]
            for j, val in enumerate(row):
                if val:
                    mask |= 1 << j
            adj[i] = mask

        best_clique = []

        def popcount(x: int) -> int:
            return x.bit_count()

        def bronk(R_mask: int, P_mask: int, X_mask: int, size_R: int):
            nonlocal best_clique
            if P_mask == 0 and X_mask == 0:
                if size_R > len(best_clique):
                    # Extract indices from R_mask
                    clique = []
                    temp = R_mask
                    while temp:
                        v = (temp & -temp).bit_length() - 1
                        clique.append(v)
                        temp &= temp - 1
                    best_clique = clique
                return
            # Prune if cannot beat current best
            if size_R + popcount(P_mask) <= len(best_clique):
                return

            # Choose pivot u from P ∪ X maximizing |P ∩ N(u)|
            union = P_mask | X_mask
            pivot = None
            max_deg = -1
            temp = union
            while temp:
                u = (temp & -temp).bit_length() - 1
                temp &= temp - 1
                deg = popcount(P_mask & adj[u])
                if deg > max_deg:
                    max_deg = deg
                    pivot = u

            # Candidates: vertices in P not adjacent to pivot
            candidates = P_mask & ~adj[pivot] if pivot is not None else P_mask
            temp = candidates
            while temp:
                v = (temp & -temp).bit_length() - 1
                temp &= temp - 1
                bronk(R_mask | (1 << v), P_mask & adj[v], X_mask & adj[v], size_R + 1)
                P_mask &= ~(1 << v)
                X_mask |= (1 << v)

        # Initial call: R empty, P all vertices, X empty
        all_vertices = (1 << n) - 1
        bronk(0, all_vertices, 0, 0)

        # Return sorted list of indices
        return sorted(best_clique)