from typing import Any
from ortools.sat.python import cp_model

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solves the minimum dominating set problem using OR-Tools CP-SAT solver.
        This implementation uses a single search worker and presolve to reduce
        overhead compared to the baseline, which can lead to faster runtimes
        while still guaranteeing optimality.
        """
        n = len(problem)
        model = cp_model.CpModel()

        # Boolean variable for each vertex: 1 if included in the dominating set
        nodes = [model.NewBoolVar(f"x_{i}") for i in range(n)]

        # Add domination constraints: each vertex must be dominated
        for i in range(n):
            # Start with the vertex itself
            neighbors = [nodes[i]]
            row = problem[i]
            for j, val in enumerate(row):
                if val:
                    neighbors.append(nodes[j])
            model.Add(sum(neighbors) >= 1)

        # Objective: minimize the number of selected vertices
        model.Minimize(sum(nodes))

        # Create solver and set parameters for speed
        solver = cp_model.CpSolver()
        solver.parameters.num_search_workers = 1  # single worker to reduce overhead
        solver.parameters.cp_model_presolve = True  # enable presolve
        # No explicit time limit; solver will run until optimality is proven

        status = solver.Solve(model)

        if status == cp_model.OPTIMAL:
            # Extract selected vertices
            return [i for i in range(n) if solver.Value(nodes[i]) == 1]
        else:
            # In case of no solution (should not happen for valid graphs)
            return []