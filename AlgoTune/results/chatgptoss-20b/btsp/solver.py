from typing import Any

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the Bottleneck Traveling Salesman Problem (BTSP).
        Returns a tour as a list of city indices starting and ending at city 0.
        """
        n = len(problem)
        if n <= 1:
            return [0, 0]

        full_mask = (1 << n) - 1
        INF = float('inf')

        # dp[mask][i] = minimal possible bottleneck for a path that visits
        # exactly the cities in 'mask' and ends at city i.
        dp = [[INF] * n for _ in range(1 << n)]
        parent = [[-1] * n for _ in range(1 << n)]

        # Start at city 0
        dp[1][0] = 0

        for mask in range(1 << n):
            if not (mask & 1):  # must include start city
                continue
            for i in range(n):
                if not (mask & (1 << i)):
                    continue
                cur_bottleneck = dp[mask][i]
                if cur_bottleneck == INF:
                    continue
                for j in range(n):
                    if mask & (1 << j):
                        continue
                    new_mask = mask | (1 << j)
                    new_bottleneck = max(cur_bottleneck, problem[i][j])
                    if new_bottleneck < dp[new_mask][j]:
                        dp[new_mask][j] = new_bottleneck
                        parent[new_mask][j] = i

        # Find best end city to close the tour
        best_bottleneck = INF
        best_end = -1
        for i in range(1, n):
            if dp[full_mask][i] == INF:
                continue
            cycle_bottleneck = max(dp[full_mask][i], problem[i][0])
            if cycle_bottleneck < best_bottleneck:
                best_bottleneck = cycle_bottleneck
                best_end = i

        if best_end == -1:
            return []

        # Reconstruct path
        path = [0]
        mask = full_mask
        cur = best_end
        while cur != 0:
            path.append(cur)
            prev = parent[mask][cur]
            mask ^= (1 << cur)
            cur = prev
        path.append(0)
        path.reverse()
        return path