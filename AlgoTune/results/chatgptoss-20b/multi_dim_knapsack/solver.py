from typing import Any
from ortools.sat.python import cp_model

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solves a multi-dimensional knapsack problem.
        Returns a list of selected item indices.
        """
        # Ensure problem is a MultiDimKnapsackInstance
        if not isinstance(problem, MultiDimKnapsackInstance):
            try:
                problem = MultiDimKnapsackInstance(*problem)
            except Exception:
                return []

        n = len(problem.value)
        k = len(problem.supply)

        model = cp_model.CpModel()
        x = [model.NewBoolVar(f"x_{i}") for i in range(n)]

        # Resource constraints
        for r in range(k):
            model.Add(sum(x[i] * problem.demand[i][r] for i in range(n)) <= problem.supply[r])

        # Objective: maximize total value
        model.Maximize(sum(x[i] * problem.value[i] for i in range(n)))

        solver = cp_model.CpSolver()
        # Optional: enable parallel search workers for speed
        solver.parameters.num_search_workers = 8
        status = solver.Solve(model)

        if status in (cp_model.OPTIMAL, cp_model.FEASIBLE):
            return [i for i in range(n) if solver.Value(x[i])]
        return []