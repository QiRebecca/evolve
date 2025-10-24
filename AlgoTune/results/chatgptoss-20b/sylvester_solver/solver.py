from typing import Any
from scipy.linalg import solve_sylvester

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        A = problem["A"]
        B = problem["B"]
        Q = problem["Q"]
        X = solve_sylvester(A, B, Q)
        return {"X": X}