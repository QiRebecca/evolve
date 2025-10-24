from typing import Any
import numpy as np
from scipy import signal

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        num = problem["num"]
        den = problem["den"]
        u = problem["u"]
        t = problem["t"]
        tout, yout, xout = signal.lsim((num, den), u, t)
        return {"yout": yout.tolist()}