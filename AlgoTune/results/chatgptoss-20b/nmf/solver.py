from typing import Any
import numpy as np
import logging
from sklearn.decomposition import NMF

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve Non-Negative Matrix Factorization using sklearn's NMF.
        Returns a dictionary with keys 'W' and 'H' containing the factor matrices.
        """
        try:
            X = np.array(problem["X"], dtype=float)
            n_components = problem["n_components"]
            model = NMF(n_components=n_components, init="random", random_state=0, max_iter=200)
            W = model.fit_transform(X)
            H = model.components_
            return {"W": W.tolist(), "H": H.tolist()}
        except Exception as e:
            logging.error(f"Error in NMF solve: {e}")
            X = np.array(problem["X"], dtype=float)
            m, n = X.shape
            n_components = problem["n_components"]
            W = np.zeros((m, n_components), dtype=float).tolist()
            H = np.zeros((n_components, n), dtype=float).tolist()
            return {"W": W, "H": H}