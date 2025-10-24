from typing import Any
import numpy as np
from scipy.special import wright_bessel
from scipy.integrate import quad

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """Integrate Wright's Bessel function over given intervals."""
        a = np.asarray(problem["a"])
        b = np.asarray(problem["b"])
        lower = np.asarray(problem["lower"])
        upper = np.asarray(problem["upper"])

        results = []
        for ai, bi, li, ui in zip(a, b, lower, upper):
            val, _ = quad(
                lambda x: wright_bessel(ai, bi, x),
                li,
                ui,
                epsabs=0,
                epsrel=1e-12,
                limit=200,
            )
            results.append(val)

        return {"result": results}