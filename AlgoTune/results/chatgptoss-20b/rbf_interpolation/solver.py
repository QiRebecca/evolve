from typing import Any
import numpy as np
from scipy.interpolate import RBFInterpolator

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        x_train = np.asarray(problem["x_train"], float)
        y_train = np.asarray(problem["y_train"], float).ravel()
        x_test = np.asarray(problem["x_test"], float)

        rbf_config = problem.get("rbf_config", {})
        kernel = rbf_config.get("kernel")
        epsilon = rbf_config.get("epsilon")
        smoothing = rbf_config.get("smoothing")

        rbf_interpolator = RBFInterpolator(
            x_train, y_train, kernel=kernel, epsilon=epsilon, smoothing=smoothing
        )

        y_pred = rbf_interpolator(x_test)

        solution = {
            "y_pred": y_pred.tolist(),
            "rbf_config": rbf_config
        }

        return solution