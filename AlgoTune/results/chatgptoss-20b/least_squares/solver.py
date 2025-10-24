from typing import Any
import numpy as np
from scipy.optimize import least_squares

class Solver:
    def solve(self, problem: dict[str, Any], **kwargs) -> Any:
        """Least squares fitting for various model types."""
        x_data = np.asarray(problem["x_data"], dtype=float)
        y_data = np.asarray(problem["y_data"], dtype=float)
        model_type = problem["model_type"]

        # Helper for safe exponentiation
        def _safe_exp(x):
            return np.exp(np.clip(x, -700, 700))

        # Polynomial case: use direct linear least squares
        if model_type == "polynomial":
            degree = problem["degree"]
            # np.polyfit returns coefficients from highest to constant
            params_opt = np.polyfit(x_data, y_data, degree)
            y_fit = np.polyval(params_opt, x_data)
            residuals = y_data - y_fit
            mse = float(np.mean(residuals**2))
            return {
                "params": params_opt.tolist(),
                "residuals": residuals.tolist(),
                "mse": mse,
                "convergence_info": {
                    "success": True,
                    "status": 1,
                    "message": "Polyfit succeeded",
                    "num_function_calls": 0,
                    "final_cost": float(np.sum(residuals**2)),
                },
            }

        # Nonlinear models
        def residual(params):
            if model_type == "exponential":
                a, b, c = params
                y_fit = a * _safe_exp(b * x_data) + c
            elif model_type == "logarithmic":
                a, b, c, d = params
                y_fit = a * np.log(np.clip(b * x_data + c, 1e-12, None)) + d
            elif model_type == "sigmoid":
                a, b, c, d = params
                y_fit = a / (1 + _safe_exp(-b * (x_data - c))) + d
            else:  # sinusoidal
                a, b, c, d = params
                y_fit = a * np.sin(b * x_data + c) + d
            return y_data - y_fit

        # Initial guess
        if model_type == "exponential":
            guess = np.array([1.0, 0.1, 0.0])
        elif model_type == "logarithmic":
            guess = np.array([1.0, 1.0, 1.0, 0.0])
        elif model_type == "sigmoid":
            guess = np.array([1.0, 1.0, 0.0, 0.0])
        else:  # sinusoidal
            guess = np.array([1.0, 1.0, 0.0, 0.0])

        # Choose method based on number of parameters
        method = "lm" if guess.size <= 10 else "trf"

        result = least_squares(
            residual,
            guess,
            method=method,
            max_nfev=10000,
            xtol=1e-12,
            ftol=1e-12,
            gtol=1e-12,
        )

        params_opt = result.x
        residuals = residual(params_opt)
        mse = float(np.mean(residuals**2))

        return {
            "params": params_opt.tolist(),
            "residuals": residuals.tolist(),
            "mse": mse,
            "convergence_info": {
                "success": result.success,
                "status": int(result.status),
                "message": result.message,
                "num_function_calls": int(result.nfev),
                "final_cost": float(np.sum(residuals**2)),
            },
        }