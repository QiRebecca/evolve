from typing import Any, List

class Solver:
    def solve(self, problem: List[List[int]], **kwargs) -> Any:
        """
        Solves the set cover problem optimally using a depth‑first search with
        iterative deepening and bitset representation. The algorithm is
        deterministic and returns the minimal set of indices (1‑indexed)
        that covers the entire universe.
        """
        # Number of subsets
        m = len(problem)
        if m == 0:
            return []

        # Determine universe size (elements are 1‑based)
        max_elem = 0
        for subset in problem:
            if subset:
                max_elem = max(max_elem, max(subset))
        n = max_elem  # universe is {1, 2, ..., n}

        # Convert each subset to a bitmask
        subset_masks: List[int] = []
        for subset in problem:
            mask = 0
            for e in subset:
                mask |= 1 << (e - 1)  # shift by e-1 because bits are 0‑based
            subset_masks.append(mask)

        # Universe mask
        universe_mask = (1 << n) - 1

        # For each element, list of subset indices that cover it
        elem_to_subsets: List[List[int]] = [[] for _ in range(n)]
        for idx, mask in enumerate(subset_masks):
            msk = mask
            while msk:
                lsb = msk & -msk
                elem_idx = (lsb.bit_length() - 1)
                elem_to_subsets[elem_idx].append(idx)
                msk -= lsb

        # Sort subsets for each element by subset size (optional, may help pruning)
        for lst in elem_to_subsets:
            lst.sort(key=lambda i: -len(subset_masks[i]))

        # Recursive DFS with iterative deepening
        def find_solution(k: int) -> List[int] | None:
            used = [False] * m

            def dfs(covered: int, depth: int) -> List[int] | None:
                if depth == k:
                    return [] if covered == universe_mask else None
                remaining = universe_mask & ~covered
                if remaining == 0:
                    return []

                # Choose uncovered element with fewest covering subsets
                min_elem = None
                min_len = 10**9
                r = remaining
                while r:
                    lsb = r & -r
                    elem_idx = (lsb.bit_length() - 1)
                    l = len(elem_to_subsets[elem_idx])
                    if l < min_len:
                        min_len = l
                        min_elem = elem_idx
                        if l == 1:
                            break
                    r -= lsb

                e = min_elem
                for si in elem_to_subsets[e]:
                    if not used[si]:
                        used[si] = True
                        res = dfs(covered | subset_masks[si], depth + 1)
                        if res is not None:
                            return [si] + res
                        used[si] = False
                return None

            return dfs(0, 0)

        # Iterative deepening from 1 to m
        for k in range(1, m + 1):
            sol = find_solution(k)
            if sol is not None:
                # Convert to 1‑indexed indices
                return [i + 1 for i in sol]

        # Should not reach here for a valid instance
        return []