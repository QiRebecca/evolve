from typing import Any, Tuple, List
from ortools.sat.python import cp_model

class Solver:
    def solve(self, problem: Tuple[int, List[List[int]], List[List[int]]], **kwargs) -> Any:
        """
        Solve the set cover with conflicts problem.

        Args:
            problem: A tuple (n, sets, conflicts) where:
                - n is the number of objects
                - sets is a list of sets (each set is a list of integers)
                - conflicts is a list of conflicts (each conflict is a list of set indices)

        Returns:
            A list of set indices that form a valid cover, or None if no solution exists
        """
        n, sets, conflicts = problem

        model = cp_model.CpModel()

        # Create binary variables for each set
        set_vars = [model.NewBoolVar(f"set_{i}") for i in range(len(sets))]

        # Ensure all objects are covered
        for obj in range(n):
            covering_sets = [set_vars[i] for i, s in enumerate(sets) if obj in s]
            if covering_sets:
                model.Add(sum(covering_sets) >= 1)

        # Add conflict constraints
        for conflict in conflicts:
            if conflict:
                model.AddAtMostOne([set_vars[i] for i in conflict])

        # Objective: minimize the number of selected sets
        model.Minimize(sum(set_vars))

        # Solve model
        solver = cp_model.CpSolver()
        solver.parameters.num_search_workers = 24
        status = solver.Solve(model)

        if status in (cp_model.OPTIMAL, cp_model.FEASIBLE):
            solution = [i for i, var in enumerate(set_vars) if solver.Value(var) == 1]
            return solution
        else:
            raise ValueError("No feasible solution found.")
