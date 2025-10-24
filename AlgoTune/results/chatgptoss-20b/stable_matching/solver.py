from typing import Any

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        prop_raw = problem["proposer_prefs"]
        recv_raw = problem["receiver_prefs"]

        if isinstance(prop_raw, dict):
            n = len(prop_raw)
            proposer_prefs = [prop_raw[i] for i in range(n)]
        else:
            proposer_prefs = list(prop_raw)
            n = len(proposer_prefs)

        if isinstance(recv_raw, dict):
            receiver_prefs = [recv_raw[i] for i in range(n)]
        else:
            receiver_prefs = list(recv_raw)

        recv_rank = [[0] * n for _ in range(n)]
        for r, prefs in enumerate(receiver_prefs):
            rank_list = recv_rank[r]
            for rank, p in enumerate(prefs):
                rank_list[p] = rank

        from collections import deque
        free = deque(range(n))
        next_prop = [0] * n
        recv_match = [-1] * n

        while free:
            p = free.popleft()
            prefs = proposer_prefs[p]
            r = prefs[next_prop[p]]
            next_prop[p] += 1

            cur = recv_match[r]
            if cur == -1:
                recv_match[r] = p
            else:
                rank_p = recv_rank[r][p]
                rank_cur = recv_rank[r][cur]
                if rank_p < rank_cur:
                    recv_match[r] = p
                    free.append(cur)
                else:
                    free.append(p)

        matching = [0] * n
        for r, p in enumerate(recv_match):
            matching[p] = r

        return {"matching": matching}