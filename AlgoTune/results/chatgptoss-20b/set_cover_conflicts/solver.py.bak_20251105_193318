from typing import Any, List, Tuple
import logging
from ortools.sat.python import cp_model

class Solver:
    def solve(self, problem, **kwargs) -> Any:
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
        # Ensure problem is a tuple
        if isinstance(problem, tuple):
            n, sets, conflicts = problem
        else:
            raise TypeError("Problem must be a tuple (n, sets, conflicts)")

        # Build a quick conflict lookup: for each set, which other sets it conflicts with
        conflict_map = [set() for _ in range(len(sets))]
        for conflict in conflicts:
            for i in conflict:
                conflict_map[i].update(conflict)
                conflict_map[i].discard(i)

        # Greedy heuristic to obtain an initial feasible solution (upper bound)
        uncovered = set(range(n))
        selected = set()
        # Precompute set coverage
        set_coverages = [set(s) for s in sets]
        # Sort sets by size descending for heuristic
        sorted_sets = sorted(range(len(sets)), key=lambda i: len(set_coverages[i]), reverse=True)

        while uncovered:
            best_set = None
            best_new = -1
            for i in sorted_sets:
                if i in selected:
                    continue
                # Check conflict with already selected
                if conflict_map[i] & selected:
                    continue
                new_covered = len(set_coverages[i] & uncovered)
                if new_covered > best_new:
                    best_new = new_covered
                    best_set = i
            if best_set is None:
                # Fallback: pick any set that covers uncovered objects ignoring conflicts
                for i in sorted_sets:
                    if i in selected:
                        continue
                    new_covered = len(set_coverages[i] & uncovered)
                    if new_covered > 0:
                        best_set = i
                        break
                if best_set is None:
                    # Should not happen because trivial sets exist
                    break
            selected.add(best_set)
            uncovered -= set_coverages[best_set]

        initial_solution = sorted(selected)

        # Build CP-SAT model
        model = cp_model.CpModel()
        set_vars = [model.NewBoolVar(f"set_{i}") for i in range(len(sets))]

        # Coverage constraints
        for obj in range(n):
            covering_vars = [set_vars[i] for i, s in enumerate(sets) if obj in s]
            model.Add(sum(covering_vars) >= 1)

        # Conflict constraints
        for conflict in conflicts:
            model.AddAtMostOne([set_vars[i] for i in conflict])

        # Objective: minimize number of selected sets
        model.Minimize(sum(set_vars))

        # Solver parameters
        solver = cp_model.CpSolver()
        solver.parameters.num_search_workers = 8
        # Use initial solution as a bound
        solver.parameters.max_time_in_seconds = 30.0  # allow up to 30 seconds if needed
        solver.parameters.log_search_progress = False

        # Provide initial solution to help pruning
        for i in initial_solution:
            solver.parameters.initial_solution = solver.parameters.initial_solution or {}
            solver.parameters.initial_solution[set_vars[i].Index()] = 1

        status = solver.Solve(model)

        if status in (cp_model.OPTIMAL, cp_model.FEASIBLE):
            solution = [i for i, var in enumerate(set_vars) if solver.Value(var) == 1]
            logging.info(f"Optimal solution found with {len(solution)} sets.")
            return solution
        else:
            logging.error("No feasible solution found.")
            raise ValueError("No feasible solution found.")