import numpy as np

try:
    # SciPy offers a thin, faster wrapper around LAPACK’s POTRF
    from scipy.linalg import cholesky as _scipy_cholesky

    def _fast_cholesky(a: np.ndarray) -> np.ndarray:
        # Use lower-triangular factor, disable redundant NaN / inf checks
        return _scipy_cholesky(a, lower=True, check_finite=False, overwrite_a=False)
except Exception:  # SciPy not present or failed to import
    def _fast_cholesky(a: np.ndarray) -> np.ndarray:  # type: ignore
        # Fallback to NumPy implementation (always available)
        return np.linalg.cholesky(a)  # NumPy always returns lower-triangular


class Solver:
    def solve(self, problem, **kwargs):
        """
        Compute the Cholesky factor L of a symmetric positive-definite matrix A.

        Parameters
        ----------
        problem : dict
            Dictionary with key "matrix" mapping to a NumPy 2-D array.

        Returns
        -------
        dict
            {"Cholesky": {"L": <numpy.ndarray>}}
        """
        A = problem["matrix"]
        # Directly call the (potentially faster) helper
        L = _fast_cholesky(A)
        return {"Cholesky": {"L": L}}