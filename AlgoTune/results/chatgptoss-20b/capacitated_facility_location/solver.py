from typing import Any
from ortools.linear_solver import pywraplp

class Solver:
    def solve(self, problem: dict[str, Any], **kwargs) -> Any:
        """
        Solves the Capacitated Facility Location Problem using OR-Tools linear solver (CBC).

        Args:
            problem: A dictionary containing problem parameters.
            **kwargs: Optional keyword arguments. Supports 'time_limit' in seconds.

        Returns:
            A dictionary containing:
                - objective_value: optimal objective value
                - facility_status: list of bools for open facilities
                - assignments: matrix x_{ij} assignments
        """
        fixed_costs = problem["fixed_costs"]
        capacities = problem["capacities"]
        demands = problem["demands"]
        transportation_costs = problem["transportation_costs"]

        n_facilities = len(fixed_costs)
        n_customers = len(demands)

        solver = pywraplp.Solver.CreateSolver('CBC')
        if solver is None:
            return {
                "objective_value": float("inf"),
                "facility_status": [False] * n_facilities,
                "assignments": [[0.0] * n_customers for _ in range(n_facilities)],
            }

        # Optional time limit
        time_limit = kwargs.get("time_limit", None)
        if time_limit is not None:
            solver.SetTimeLimit(int(time_limit * 1000))

        # Variables
        y = [solver.IntVar(0, 1, f'y_{i}') for i in range(n_facilities)]
        x = [[solver.IntVar(0, 1, f'x_{i}_{j}') for j in range(n_customers)] for i in range(n_facilities)]

        # Each customer served by exactly one facility
        for j in range(n_customers):
            solver.Add(solver.Sum(x[i][j] for i in range(n_facilities)) == 1)

        # Capacity constraints and linkage
        for i in range(n_facilities):
            # Capacity
            solver.Add(solver.Sum(demands[j] * x[i][j] for j in range(n_customers)) <= capacities[i] * y[i])
            # Link x <= y
            for j in range(n_customers):
                solver.Add(x[i][j] <= y[i])

        # Objective
        objective_terms = []
        for i in range(n_facilities):
            objective_terms.append(fixed_costs[i] * y[i])
            for j in range(n_customers):
                objective_terms.append(transportation_costs[i][j] * x[i][j])
        solver.Minimize(solver.Sum(objective_terms))

        status = solver.Solve()

        if status not in (pywraplp.Solver.OPTIMAL, pywraplp.Solver.FEASIBLE):
            return {
                "objective_value": float("inf"),
                "facility_status": [False] * n_facilities,
                "assignments": [[0.0] * n_customers for _ in range(n_facilities)],
            }

        facility_status = [bool(solver.Value(y[i])) for i in range(n_facilities)]
        assignments = [[float(solver.Value(x[i][j])) for j in range(n_customers)] for i in range(n_facilities)]
        objective_value = solver.Objective().Value()

        return {
            "objective_value": float(objective_value),
            "facility_status": facility_status,
            "assignments": assignments,
        }