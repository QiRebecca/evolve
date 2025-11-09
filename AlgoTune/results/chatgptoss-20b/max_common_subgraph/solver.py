from typing import Any

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        A = problem["A"]
        B = problem["B"]
        n = len(A)
        m = len(B)
        V = n * m
        # Map vertex index to (i, p)
        pairs = [(i, p) for i in range(n) for p in range(m)]
        # Build adjacency bitmask for each vertex
        adj = [0] * V
        for idx1 in range(V):
            i, p = pairs[idx1]
            mask = 0
            for idx2 in range(idx1 + 1, V):
                j, q = pairs[idx2]
                if i == j or p == q:
                    continue
                if A[i][j] == B[p][q]:
                    mask |= 1 << idx2
                    adj[idx2] |= 1 << idx1
            adj[idx1] = mask

        best_clique = set()

        def bk(R: set, P: int, X: int):
            nonlocal best_clique
            if P == 0 and X == 0:
                if len(R) > len(best_clique):
                    best_clique = set(R)
                return
            # Prune if even adding all remaining vertices cannot beat current best
            if len(R) + P.bit_count() <= len(best_clique):
                return
            # Choose pivot u from P ∪ X with maximum degree in P
            union = P | X
            # Pick any pivot (lowest set bit)
            u_bit = union & -union
            u_idx = u_bit.bit_length() - 1
            # Candidates are vertices in P not adjacent to pivot
            candidates = P & ~adj[u_idx]
            while candidates:
                v_bit = candidates & -candidates
                v_idx = v_bit.bit_length() - 1
                bk(R | {v_idx}, P & adj[v_idx], X & adj[v_idx])
                P &= ~v_bit
                X |= v_bit
                candidates &= ~v_bit

        all_vertices = (1 << V) - 1
        bk(set(), all_vertices, 0)

        # Convert best clique indices to list of (i, p) pairs
        result = [pairs[idx] for idx in best_clique]
        # Sort for deterministic output
        result.sort()
        return result