from typing import Any
import numpy as np
from sklearn.linear_model import Lasso
import logging

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        try:
            clf = Lasso(alpha=0.1, fit_intercept=False, max_iter=10000)
            clf.fit(problem["X"], problem["y"])
            return clf.coef_.tolist()
        except Exception as e:
            logging.error(f"Error: {e}")
            X = np.array(problem["X"])
            _, d = X.shape
            return np.zeros(d).tolist()