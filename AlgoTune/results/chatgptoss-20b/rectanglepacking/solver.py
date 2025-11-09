from typing import Any
import itertools
from ortools.sat.python import cp_model

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        instance = problem

        class RectangleKnapsackWithRotationsModel:
            def __init__(self, instance):
                self.instance = instance
                self.model = cp_model.CpModel()

                # Create variables for each rectangle
                self.bottom_left_x_vars = [
                    self.model.NewIntVar(0, instance.container_width, f"x1_{i}")
                    for i, _ in enumerate(instance.rectangles)
                ]
                self.bottom_left_y_vars = [
                    self.model.NewIntVar(0, instance.container_height, f"y1_{i}")
                    for i, _ in enumerate(instance.rectangles)
                ]
                self.upper_right_x_vars = [
                    self.model.NewIntVar(0, instance.container_width, f"x2_{i}")
                    for i, _ in enumerate(instance.rectangles)
                ]
                self.upper_right_y_vars = [
                    self.model.NewIntVar(0, instance.container_height, f"y2_{i}")
                    for i, _ in enumerate(instance.rectangles)
                ]
                self.rotated_vars = [
                    self.model.NewBoolVar(f"rotated_{i}") for i in range(len(instance.rectangles))
                ]
                self.placed_vars = [
                    self.model.NewBoolVar(f"placed_{i}") for i in range(len(instance.rectangles))
                ]

                # Constraints for rectangle dimensions and placement
                for i, rect in enumerate(instance.rectangles):
                    if rect.rotatable:
                        # Not rotated
                        self.model.Add(
                            self.upper_right_x_vars[i] == self.bottom_left_x_vars[i] + rect.width
                        ).OnlyEnforceIf([self.placed_vars[i], self.rotated_vars[i].Not()])
                        self.model.Add(
                            self.upper_right_y_vars[i] == self.bottom_left_y_vars[i] + rect.height
                        ).OnlyEnforceIf([self.placed_vars[i], self.rotated_vars[i].Not()])

                        # Rotated
                        self.model.Add(
                            self.upper_right_x_vars[i] == self.bottom_left_x_vars[i] + rect.height
                        ).OnlyEnforceIf([self.placed_vars[i], self.rotated_vars[i]])
                        self.model.Add(
                            self.upper_right_y_vars[i] == self.bottom_left_y_vars[i] + rect.width
                        ).OnlyEnforceIf([self.placed_vars[i], self.rotated_vars[i]])
                    else:
                        # Not rotatable
                        self.model.Add(
                            self.upper_right_x_vars[i] == self.bottom_left_x_vars[i] + rect.width
                        ).OnlyEnforceIf(self.placed_vars[i])
                        self.model.Add(
                            self.upper_right_y_vars[i] == self.bottom_left_y_vars[i] + rect.height
                        ).OnlyEnforceIf(self.placed_vars[i])
                        self.model.Add(self.rotated_vars[i] == 0)

                    # If not placed, coordinates are zero
                    self.model.Add(self.bottom_left_x_vars[i] == 0).OnlyEnforceIf(self.placed_vars[i].Not())
                    self.model.Add(self.bottom_left_y_vars[i] == 0).OnlyEnforceIf(self.placed_vars[i].Not())
                    self.model.Add(self.upper_right_x_vars[i] == 0).OnlyEnforceIf(self.placed_vars[i].Not())
                    self.model.Add(self.upper_right_y_vars[i] == 0).OnlyEnforceIf(self.placed_vars[i].Not())

                # Non-overlap constraints
                for i, j in itertools.combinations(range(len(instance.rectangles)), 2):
                    b_i_left_of_j = self.model.NewBoolVar(f"{i}_left_of_{j}")
                    self.model.Add(
                        self.upper_right_x_vars[i] <= self.bottom_left_x_vars[j]
                    ).OnlyEnforceIf([self.placed_vars[i], self.placed_vars[j], b_i_left_of_j])

                    b_i_right_of_j = self.model.NewBoolVar(f"{i}_right_of_{j}")
                    self.model.Add(
                        self.bottom_left_x_vars[i] >= self.upper_right_x_vars[j]
                    ).OnlyEnforceIf([self.placed_vars[i], self.placed_vars[j], b_i_right_of_j])

                    b_i_below_j = self.model.NewBoolVar(f"{i}_below_{j}")
                    self.model.Add(
                        self.upper_right_y_vars[i] <= self.bottom_left_y_vars[j]
                    ).OnlyEnforceIf([self.placed_vars[i], self.placed_vars[j], b_i_below_j])

                    b_i_above_j = self.model.NewBoolVar(f"{i}_above_{j}")
                    self.model.Add(
                        self.bottom_left_y_vars[i] >= self.upper_right_y_vars[j]
                    ).OnlyEnforceIf([self.placed_vars[i], self.placed_vars[j], b_i_above_j])

                    self.model.Add(
                        b_i_left_of_j + b_i_right_of_j + b_i_below_j + b_i_above_j >= 1
                    ).OnlyEnforceIf([self.placed_vars[i], self.placed_vars[j]])

                # Objective: maximize number of placed rectangles
                self.model.Maximize(sum(self.placed_vars))

            def _extract_solution(self, solver):
                solution = []
                for i in range(len(self.instance.rectangles)):
                    if solver.Value(self.placed_vars[i]):
                        x = solver.Value(self.bottom_left_x_vars[i])
                        y = solver.Value(self.bottom_left_y_vars[i])
                        rotated = solver.Value(self.rotated_vars[i]) == 1
                        solution.append(RectanglePlacement(i, x, y, rotated))
                return solution

            def solve(self, time_limit=900.0):
                solver = cp_model.CpSolver()
                solver.parameters.max_time_in_seconds = time_limit
                solver.parameters.num_search_workers = 8
                status = solver.Solve(self.model)
                if status in (cp_model.OPTIMAL, cp_model.FEASIBLE):
                    return self._extract_solution(solver)
                return []

        model = RectangleKnapsackWithRotationsModel(instance)
        return model.solve()