from typing import Any
import networkx as nx

class Solver:
    def solve(self, problem: dict[str, Any], **kwargs) -> Any:
        """
        Solve the Dynamic Assortment Planning problem using a min-cost flow formulation.
        """
        T = problem["T"]
        N = problem["N"]
        prices = problem["prices"]
        capacities = problem["capacities"]
        probs = problem["probs"]

        G = nx.DiGraph()

        # Source and sink with demands
        G.add_node("s", demand=-T)
        G.add_node("t", demand=T)

        # Dummy idle node to allow periods to stay idle
        G.add_node("idle", demand=0)
        G.add_edge("idle", "t", capacity=T, weight=0)

        # Product nodes
        for i in range(N):
            pi = f"pi{i}"
            G.add_node(pi, demand=0)
            G.add_edge(pi, "t", capacity=capacities[i], weight=0)

        # Period nodes and edges
        for t in range(T):
            pt = f"p{t}"
            G.add_node(pt, demand=0)
            G.add_edge("s", pt, capacity=1, weight=0)

            # Edge to idle (stay idle)
            G.add_edge(pt, "idle", capacity=1, weight=0)

            for i in range(N):
                pi = f"pi{i}"
                w = prices[i] * probs[t][i]
                G.add_edge(pt, pi, capacity=1, weight=-w)

        # Solve min-cost flow
        _, flow_dict = nx.network_simplex(G)

        # Extract assignment
        offer = [-1] * T
        for t in range(T):
            pt = f"p{t}"
            for i in range(N):
                pi = f"pi{i}"
                if flow_dict[pt].get(pi, 0) == 1:
                    offer[t] = i
                    break
        return offer