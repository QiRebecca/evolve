from typing import Any
import numpy as np
from ortools.sat.python import cp_model

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solves the Queens with Obstacles Problem using CP-SAT with pairwise attack constraints.
        """
        instance = problem
        n, m = instance.shape
        model = cp_model.CpModel()

        # Decision variables
        queens = [[model.NewBoolVar(f"q_{r}_{c}") for c in range(m)] for r in range(n)]

        # No queens on obstacles
        for r in range(n):
            for c in range(m):
                if instance[r, c]:
                    model.Add(queens[r][c] == 0)

        # Directions for queen moves
        directions = [(-1, 0), (1, 0), (0, -1), (0, 1),
                      (-1, -1), (-1, 1), (1, -1), (1, 1)]

        # Add pairwise attack constraints
        for r in range(n):
            for c in range(m):
                if instance[r, c]:
                    continue
                for dr, dc in directions:
                    nr, nc = r + dr, c + dc
                    while 0 <= nr < n and 0 <= nc < m and not instance[nr, nc]:
                        model.Add(queens[r][c] + queens[nr][nc] <= 1)
                        nr += dr
                        nc += dc

        # Objective: maximize number of queens
        model.Maximize(sum(queens[r][c] for r in range(n) for c in range(m)))

        solver = cp_model.CpSolver()
        solver.parameters.num_search_workers = 8
        solver.parameters.log_search_progress = False

        status = solver.Solve(model)

        if status == cp_model.OPTIMAL or status == cp_model.FEASIBLE:
            return [(r, c) for r in range(n) for c in range(m) if solver.Value(queens[r][c])]
        else:
            return []