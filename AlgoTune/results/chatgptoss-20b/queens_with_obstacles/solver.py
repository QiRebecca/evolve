from typing import Any
import numpy as np
from ortools.sat.python import cp_model

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        board = problem
        n, m = board.shape
        free_cells = [(r, c) for r in range(n) for c in range(m) if not board[r, c]]
        idx = {cell: i for i, cell in enumerate(free_cells)}
        num_cells = len(free_cells)

        model = cp_model.CpModel()
        x = [model.NewBoolVar(f"x_{i}") for i in range(num_cells)]

        directions = [(-1, 0), (1, 0), (0, -1), (0, 1),
                      (-1, -1), (-1, 1), (1, -1), (1, 1)]

        for i, (r, c) in enumerate(free_cells):
            for dr, dc in directions:
                nr, nc = r + dr, c + dc
                while 0 <= nr < n and 0 <= nc < m and not board[nr, nc]:
                    j = idx[(nr, nc)]
                    if i < j:
                        model.Add(x[i] + x[j] <= 1)
                    nr += dr
                    nc += dc

        model.Maximize(sum(x))

        solver = cp_model.CpSolver()
        solver.parameters.num_search_workers = 8
        solver.parameters.cp_model_presolve = True
        solver.parameters.linearization_level = 0
        solver.parameters.max_time_in_seconds = 60.0
        solver.parameters.log_search_progress = False

        status = solver.Solve(model)

        if status == cp_model.OPTIMAL or status == cp_model.FEASIBLE:
            return [(free_cells[i][0], free_cells[i][1]) for i in range(num_cells) if solver.Value(x[i]) == 1]
        return []