from typing import Any
import numpy as np
import math

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the channel capacity problem using the Blahut–Arimoto algorithm.
        """
        # Extract transition matrix
        P = np.array(problem.get("P", []), dtype=float)
        if P.ndim != 2:
            return None
        m, n = P.shape

        # Validate that columns sum to 1 (within tolerance)
        if not np.allclose(P.sum(axis=0), 1.0, atol=1e-6):
            # Allow small deviations but warn
            pass

        # Initialize input distribution uniformly
        x = np.full(n, 1.0 / n, dtype=float)

        # Precompute log2 of P where P>0
        logP = np.zeros_like(P)
        mask_pos = P > 0
        logP[mask_pos] = np.log2(P[mask_pos])

        # Precompute sum_i P_ij * log2(P_ij) for each input j
        # This is used in the capacity calculation
        sumP_logP = np.sum(P * logP, axis=0)  # shape (n,)

        # Blahut–Arimoto iterations
        tol = 1e-9
        max_iter = 1000
        prev_C = -np.inf

        for _ in range(max_iter):
            # Compute output distribution y = P @ x
            y = P @ x  # shape (m,)

            # Avoid division by zero: set zero entries to 1 for log division (will be masked)
            y_safe = np.where(y > 0, y, 1.0)

            # Compute log2(y_i) where y_i > 0
            logy = np.zeros_like(y)
            mask_y = y > 0
            logy[mask_y] = np.log2(y[mask_y])

            # Compute the exponent factor for each input j:
            # exp2( sum_i P_ij * (log2(P_ij) - log2(y_i)) )
            # Use broadcasting: P * (logP - logy[:,None])
            diff = logP - logy[:, None]
            # For entries where P==0, the product is zero
            weighted = P * diff
            # Sum over outputs
            sum_weighted = np.sum(weighted, axis=0)  # shape (n,)
            # Exponentiate base 2
            factor = 2.0 ** sum_weighted
            # Update x
            x_new = x * factor
            # Normalize
            x_new /= x_new.sum()

            # Compute capacity I = H(Y) - H(Y|X)
            # H(Y) = - sum_i y_i * log2(y_i)
            H_Y = -np.sum(y[mask_y] * logy[mask_y])
            # H(Y|X) = - sum_j x_j * sum_i P_ij * log2(P_ij)
            H_Y_given_X = -np.sum(x_new * sumP_logP)
            C = H_Y - H_Y_given_X

            # Check convergence
            if abs(C - prev_C) < tol:
                x = x_new
                prev_C = C
                break

            x = x_new
            prev_C = C

        # Final capacity value
        C_final = prev_C

        return {"x": x.tolist(), "C": float(C_final)}