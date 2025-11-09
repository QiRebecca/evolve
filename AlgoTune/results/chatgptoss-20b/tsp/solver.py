from typing import Any
from ortools.sat.python import cp_model

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the TSP problem using CP-SAT solver with minimal overhead.

        :param problem: Distance matrix as a list of lists.
        :return: A list representing the optimal tour, starting and ending at city 0.
        """
        n = len(problem)

        if n <= 1:
            return [0, 0]

        model = cp_model.CpModel()

        # Create variables
        x = {(i, j): model.NewBoolVar(f"x[{i},{j}]") for i in range(n) for j in range(n) if i != j}

        # Circuit constraint
        model.AddCircuit([(u, v, var) for (u, v), var in x.items()])

        # Add objective
        model.Minimize(sum(problem[i][j] * x[i, j] for i in range(n) for j in range(n) if i != j))

        # Solve the model
        solver = cp_model.CpSolver()
        # Reduce overhead: single worker, no logging
        solver.parameters.num_search_workers = 1
        solver.parameters.log_search_progress = False

        status = solver.Solve(model)

        if status in (cp_model.OPTIMAL, cp_model.FEASIBLE):
            path = []
            current_city = 0
            while len(path) < n:
                path.append(current_city)
                for next_city in range(n):
                    if current_city != next_city and solver.Value(x[current_city, next_city]) == 1:
                        current_city = next_city
                        break
            path.append(0)  # Return to the starting city
            return path
        else:
            return []