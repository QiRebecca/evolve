from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        vec1, vec2 = problem
        return np.array(vec1)[:, None] * np.array(vec2)