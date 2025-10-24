from typing import Any

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the maximum flow with minimum cost problem.
        The implementation uses the successive shortest augmenting path algorithm
        with potentials (Johnson's algorithm) for min-cost max-flow.
        """
        import heapq

        n = len(problem["capacity"])
        s = problem["s"]
        t = problem["t"]
        capacity = problem["capacity"]
        cost = problem["cost"]

        # Build residual graph
        graph = [[] for _ in range(n)]

        def add_edge(u, v, cap, cst):
            # forward edge
            graph[u].append({"to": v, "rev": len(graph[v]), "cap": cap, "cost": cst, "orig": (u, v)})
            # reverse edge
            graph[v].append({"to": u, "rev": len(graph[u]) - 1, "cap": 0, "cost": -cst, "orig": None})

        for i in range(n):
            for j in range(n):
                if capacity[i][j] > 0:
                    add_edge(i, j, capacity[i][j], cost[i][j])

        # potentials for reduced costs
        h = [0] * n
        flow_matrix = [[0] * n for _ in range(n)]
        max_flow = 0
        min_cost = 0

        INF = 10**18

        while True:
            dist = [INF] * n
            dist[s] = 0
            prevnode = [-1] * n
            prevedge = [-1] * n
            inqueue = [False] * n
            pq = [(0, s)]
            while pq:
                d, u = heapq.heappop(pq)
                if d != dist[u]:
                    continue
                for ei, e in enumerate(graph[u]):
                    if e["cap"] > 0:
                        v = e["to"]
                        nd = d + e["cost"] + h[u] - h[v]
                        if nd < dist[v]:
                            dist[v] = nd
                            prevnode[v] = u
                            prevedge[v] = ei
                            heapq.heappush(pq, (nd, v))
            if dist[t] == INF:
                break

            # update potentials
            for v in range(n):
                if dist[v] < INF:
                    h[v] += dist[v]

            # find bottleneck
            d = INF
            v = t
            while v != s:
                u = prevnode[v]
                ei = prevedge[v]
                e = graph[u][ei]
                if e["cap"] < d:
                    d = e["cap"]
                v = u

            # augment
            v = t
            while v != s:
                u = prevnode[v]
                ei = prevedge[v]
                e = graph[u][ei]
                e["cap"] -= d
                rev = e["rev"]
                graph[v][rev]["cap"] += d
                if e["orig"] is not None:
                    ui, vi = e["orig"]
                    flow_matrix[ui][vi] += d
                v = u

            max_flow += d
            min_cost += d * h[t]

        return flow_matrix