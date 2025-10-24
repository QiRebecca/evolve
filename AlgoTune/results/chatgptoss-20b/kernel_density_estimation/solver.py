from typing import Any
import numpy as np
from numbers import Real
from scipy.special import logsumexp
import math

class Solver:
    # Supported kernels
    available_kernels = {
        "gaussian",
        "tophat",
        "epanechnikov",
        "exponential",
        "linear",
        "cosine",
    }

    def solve(self, problem: dict[str, Any], **kwargs) -> Any:
        """
        Compute the log-density of a kernel density estimate at query points.

        Parameters
        ----------
        problem : dict
            Dictionary containing the following keys:
                - "data_points": array-like of shape (n, d)
                - "query_points": array-like of shape (m, d)
                - "kernel": str, one of the supported kernels
                - "bandwidth": positive float

        Returns
        -------
        dict
            {"log_density": list of floats} or {"error": str}
        """
        try:
            # Parse inputs
            X = np.asarray(problem["data_points"], dtype=float)
            X_q = np.asarray(problem["query_points"], dtype=float)
            kernel = problem["kernel"]
            bandwidth = problem["bandwidth"]

            # Basic shape checks
            if X.ndim != 2 or X_q.ndim != 2:
                raise ValueError("Data points or query points are not 2D arrays.")
            if X.shape[0] == 0:
                raise ValueError("No data points provided.")
            if X_q.shape[0] == 0:
                return {"log_density": []}
            if X.shape[1] != X_q.shape[1]:
                raise ValueError("Data points and query points have different dimensions.")

            # Validate bandwidth
            if not isinstance(bandwidth, Real) or bandwidth <= 0:
                raise ValueError("Bandwidth must be positive.")
            h = float(bandwidth)

            # Validate kernel
            if kernel not in self.available_kernels:
                raise ValueError(f"Unknown kernel: {kernel}")

            n, d = X.shape
            m = X_q.shape[0]

            # Precompute constants
            if kernel == "gaussian":
                # Normalization constant for Gaussian kernel
                norm_const = -d * math.log(h) - (d / 2) * math.log(2 * math.pi)
                # Compute pairwise squared distances
                diff = X_q[:, None, :] - X[None, :, :]  # shape (m, n, d)
                sq_dist = np.sum(diff ** 2, axis=2)  # shape (m, n)
                # log sum exp of -sq_dist/(2h^2)
                log_weights = -sq_dist / (2 * h * h)
                log_sum = logsumexp(log_weights, axis=1)  # shape (m,)
                log_density = norm_const - math.log(n) + log_sum
                return {"log_density": log_density.tolist()}

            # For other kernels, compute kernel values directly
            # Compute pairwise distances
            diff = X_q[:, None, :] - X[None, :, :]
            dist = np.linalg.norm(diff, axis=2)  # shape (m, n)

            if kernel == "tophat":
                # Indicator of distance <= h
                mask = dist <= h
                count = np.sum(mask, axis=1)  # shape (m,)
                # Volume of d-dimensional unit ball
                V_d = math.pi ** (d / 2) / math.gamma(d / 2 + 1)
                vol = V_d * h ** d
                # Density: count / (n * vol)
                density = count / (n * vol)
                # log density
                log_density = np.where(density > 0, np.log(density), -np.inf)
                return {"log_density": log_density.tolist()}

            if kernel == "epanechnikov":
                # Kernel value: (1 - (r/h)^2) for r <= h
                r_over_h = dist / h
                mask = r_over_h <= 1
                kernel_vals = np.where(mask, 1 - r_over_h ** 2, 0)
                sum_k = np.sum(kernel_vals, axis=1)  # shape (m,)
                # Normalization constant: integral of kernel over unit ball
                V_d = math.pi ** (d / 2) / math.gamma(d / 2 + 1)
                C_d = V_d / (d + 2)  # integral of (1 - r^2) over unit ball
                density = (d + 2) * sum_k / (n * h ** d * V_d)
                log_density = np.where(density > 0, np.log(density), -np.inf)
                return {"log_density": log_density.tolist()}

            if kernel == "exponential":
                # Kernel: exp(-||x||/h)
                kernel_vals = np.exp(-dist / h)
                sum_k = np.sum(kernel_vals, axis=1)
                # Normalization constant for exponential kernel in d dimensions
                # Integral of exp(-r/h) * r^(d-1) dr from 0 to inf = h^d * (d-1)!
                # So density = sum_k / (n * h^d * (d-1)!)
                fact = math.factorial(d - 1) if d > 0 else 1
                density = sum_k / (n * h ** d * fact)
                log_density = np.where(density > 0, np.log(density), -np.inf)
                return {"log_density": log_density.tolist()}

            if kernel == "linear":
                # Kernel: max(0, 1 - ||x||/h)
                kernel_vals = np.maximum(0, 1 - dist / h)
                sum_k = np.sum(kernel_vals, axis=1)
                # Normalization constant: integral of (1 - r/h) over unit ball
                V_d = math.pi ** (d / 2) / math.gamma(d / 2 + 1)
                # Integral = V_d * h^d * (1/(d+1))
                density = sum_k / (n * h ** d * V_d / (d + 1))
                log_density = np.where(density > 0, np.log(density), -np.inf)
                return {"log_density": log_density.tolist()}

            if kernel == "cosine":
                # Kernel: max(0, cos(pi * ||x|| / (2h))) for ||x|| <= h
                mask = dist <= h
                kernel_vals = np.where(mask, np.cos(math.pi * dist / (2 * h)), 0)
                sum_k = np.sum(kernel_vals, axis=1)
                # Normalization constant: integral of cos(pi r/(2h)) over unit ball
                # Integral = V_d * h^d * (2 / (pi * (d+1))) * sin(pi/2) = V_d * h^d * (2 / (pi * (d+1)))
                V_d = math.pi ** (d / 2) / math.gamma(d / 2 + 1)
                density = sum_k / (n * h ** d * V_d * (2 / (math.pi * (d + 1))))
                log_density = np.where(density > 0, np.log(density), -np.inf)
                return {"log_density": log_density.tolist()}

            # If kernel not handled (should not happen)
            raise ValueError(f"Kernel '{kernel}' not implemented.")

        except KeyError as e:
            return {"error": f"Missing key: {e}"}
        except (ValueError, TypeError) as e:
            return {"error": f"Computation error: {e}"}
        except Exception as e:
            return {"error": f"Unexpected error: {e}"}