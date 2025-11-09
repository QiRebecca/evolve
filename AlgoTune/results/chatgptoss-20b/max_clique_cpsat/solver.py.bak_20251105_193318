from typing import Any

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solves the maximum clique problem using a branch‑and‑bound
        implementation of the Bron–Kerbosch algorithm with pivoting
        and bitset representation for speed.
        """
        n = len(problem)
        if n == 0:
            return []

        # Build adjacency bitmasks (without self loops)
        adjacency = [0] * n
        for i in range(n):
            mask = 0
            row = problem[i]
            for j, val in enumerate(row):
                if val:
                    mask |= 1 << j
            adjacency[i] = mask

        # Initial sets: all vertices in P, R and X empty
        all_vertices = (1 << n) - 1
        best_clique_mask = 0

        def bit_count(x: int) -> int:
            return x.bit_count()

        def bronk(R: int, P: int, X: int):
            nonlocal best_clique_mask

            # Prune if even adding all remaining vertices cannot beat current best
            if bit_count(R) + bit_count(P) <= bit_count(best_clique_mask):
                return

            if P == 0 and X == 0:
                # Found a maximal clique
                if bit_count(R) > bit_count(best_clique_mask):
                    best_clique_mask = R
                return

            # Choose a pivot u from P ∪ X
            # Heuristic: pick vertex with maximum degree in P
            union = P | X
            if union:
                # Pick pivot with most neighbors in P
                max_deg = -1
                pivot = None
                temp = union
                while temp:
                    u = temp & -temp
                    idx = (u.bit_length() - 1)
                    deg = bit_count(P & adjacency[idx])
                    if deg > max_deg:
                        max_deg = deg
                        pivot = idx
                    temp &= temp - 1
                u_mask = 1 << pivot
            else:
                u_mask = 0

            # Candidates are vertices in P not adjacent to pivot
            candidates = P & ~adjacency[pivot] if union else P

            while candidates:
                v_mask = candidates & -candidates
                v = v_mask.bit_length() - 1
                candidates -= v_mask

                bronk(R | v_mask, P & adjacency[v], X & adjacency[v])

                P -= v_mask
                X |= v_mask

        bronk(0, all_vertices, 0)

        # Convert best clique bitmask to list of indices
        result = [i for i in range(n) if (best_clique_mask >> i) & 1]
        return result