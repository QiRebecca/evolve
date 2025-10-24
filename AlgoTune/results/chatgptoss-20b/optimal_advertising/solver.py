from typing import Any
import numpy as np
import pulp


class Solver:
    def solve(self, problem: dict, **kwargs) -> Any:
        """
        Solve the optimal advertising problem using a linear programming formulation.
        The objective is linearized by introducing auxiliary variables for clicks and revenue.
        """
        # Extract problem parameters
        P = np.array(problem["P"])
        R = np.array(problem["R"])
        B = np.array(problem["B"])
        c = np.array(problem["c"])
        T = np.array(problem["T"])

        m, n = P.shape

        # Create LP problem
        prob = pulp.LpProblem("OptimalAdvertising", pulp.LpMaximize)

        # Decision variables: displays D[i][t]
        D = pulp.LpVariable.dicts(
            "D",
            ((i, t) for i in range(m) for t in range(n)),
            lowBound=0,
            cat=pulp.LpContinuous,
        )

        # Auxiliary variables: total clicks per ad
        x = pulp.LpVariable.dicts(
            "x",
            (i for i in range(m)),
            lowBound=0,
            cat=pulp.LpContinuous,
        )

        # Auxiliary variables: revenue per ad
        y = pulp.LpVariable.dicts(
            "y",
            (i for i in range(m)),
            lowBound=0,
            cat=pulp.LpContinuous,
        )

        # Constraints
        # Minimum display requirements per ad
        for i in range(m):
            prob += (
                pulp.lpSum(D[(i, t)] for t in range(n)) >= c[i],
                f"min_display_ad_{i}",
            )

        # Traffic capacity per time slot
        for t in range(n):
            prob += (
                pulp.lpSum(D[(i, t)] for i in range(m)) <= T[t],
                f"traffic_capacity_t_{t}",
            )

        # Click definition: x_i = sum_t P_it * D_it
        for i in range(m):
            prob += (
                pulp.lpSum(P[i, t] * D[(i, t)] for t in range(n)) == x[i],
                f"click_def_ad_{i}",
            )

        # Revenue definition: y_i <= R_i * x_i and y_i <= B_i
        for i in range(m):
            prob += (
                y[i] <= R[i] * x[i],
                f"rev_cap1_ad_{i}",
            )
            prob += (
                y[i] <= B[i],
                f"rev_cap2_ad_{i}",
            )

        # Objective: maximize total revenue
        prob += pulp.lpSum(y[i] for i in range(m)), "TotalRevenue"

        # Solve the problem
        prob.solve()

        status_str = pulp.LpStatus[prob.status]
        optimal = prob.status == pulp.LpStatusOptimal

        if not optimal:
            return {
                "status": status_str,
                "optimal": False,
                "error": f"Solver status: {status_str}",
            }

        # Retrieve display matrix
        displays = np.zeros((m, n))
        for i in range(m):
            for t in range(n):
                displays[i, t] = D[(i, t)].value()

        # Compute clicks and revenue per ad
        clicks = np.zeros(m)
        revenue_per_ad = np.zeros(m)
        for i in range(m):
            clicks[i] = np.sum(P[i, :] * displays[i, :])
            revenue_per_ad[i] = min(R[i] * clicks[i], B[i])

        total_revenue = float(np.sum(revenue_per_ad))

        return {
            "status": status_str,
            "optimal": True,
            "displays": displays.tolist(),
            "clicks": clicks.tolist(),
            "revenue_per_ad": revenue_per_ad.tolist(),
            "total_revenue": total_revenue,
            "objective_value": float(prob.objective.value()),
        }