from typing import Any

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve a multi-dimensional knapsack problem.

        Parameters
        ----------
        problem : tuple or list or object
            Either a tuple/list of (value, demand, supply) or an object
            with attributes `value`, `demand`, and `supply`.

        Returns
        -------
        list[int]
            List of selected item indices that maximize total value
            while respecting all resource constraints.
        """
        # Parse problem input
        if isinstance(problem, (list, tuple)):
            if len(problem) != 3:
                return []
            value, demand, supply = problem
        else:
            try:
                value = problem.value
                demand = problem.demand
                supply = problem.supply
            except Exception:
                return []

        n = len(value)
        k = len(supply)

        # Build CP-SAT model
        from ortools.sat.python import cp_model

        model = cp_model.CpModel()
        x = [model.NewBoolVar(f"x_{i}") for i in range(n)]

        # Resource constraints
        for r in range(k):
            model.Add(sum(x[i] * demand[i][r] for i in range(n)) <= supply[r])

        # Objective: maximize total value
        model.Maximize(sum(x[i] * value[i] for i in range(n)))

        # Solve
        solver = cp_model.CpSolver()
        solver.parameters.num_threads = 24  # Use up to 24 threads
        status = solver.Solve(model)

        if status in (cp_model.OPTIMAL, cp_model.FEASIBLE):
            return [i for i in range(n) if solver.Value(x[i]) == 1]
        return []