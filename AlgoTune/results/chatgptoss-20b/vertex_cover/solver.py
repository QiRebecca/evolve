from typing import Any
import pulp

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solves the minimum vertex cover problem using an integer linear programming formulation.
        :param problem: a 2d-array (adjacency matrix)
        :return: A list indicating the selected nodes
        """
        n = len(problem)
        if n == 0:
            return []

        # Create the ILP problem
        prob = pulp.LpProblem("VertexCover", pulp.LpMinimize)

        # Decision variables: x_i = 1 if vertex i is in the cover
        x = [pulp.LpVariable(f"x_{i}", cat='Binary') for i in range(n)]

        # Objective: minimize the number of selected vertices
        prob += pulp.lpSum(x)

        # Constraints: for each edge (i, j), at least one endpoint must be selected
        for i in range(n):
            for j in range(i + 1, n):
                if problem[i][j]:
                    prob += x[i] + x[j] >= 1

        # Solve the ILP
        try:
            prob.solve(pulp.PULP_CBC_CMD(msg=False))
        except Exception:
            # In case the solver fails, return all vertices as a fallback
            return list(range(n))

        # Extract the selected vertices
        selected = [i for i in range(n) if pulp.value(x[i]) > 0.5]
        return selected