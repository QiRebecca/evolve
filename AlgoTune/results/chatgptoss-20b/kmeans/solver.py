from typing import Any
import logging
import numpy as np
from sklearn.cluster import MiniBatchKMeans

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        try:
            X = problem["X"]
            k = problem["k"]
            # Use MiniBatchKMeans for faster convergence
            mbk = MiniBatchKMeans(
                n_clusters=k,
                batch_size=256,
                max_iter=200,
                init='k-means++',
                n_init=1,
                random_state=0
            )
            mbk.fit(X)
            return mbk.labels_.tolist()
        except Exception as e:
            logging.error(f"Error: {e}")
            n = len(problem["X"])
            return [0] * n