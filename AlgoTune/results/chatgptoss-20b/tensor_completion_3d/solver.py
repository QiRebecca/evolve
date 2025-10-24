from typing import Any
import numpy as np
import cvxpy as cp
import logging

class Solver:
    def solve(self, problem: dict, **kwargs) -> Any:
        """
        Solve the 3D tensor completion problem using nuclear norm minimization
        on the mode‑unfoldings.  The implementation follows the baseline
        but is optimised for speed by avoiding explicit loops where possible.
        """
        # Extract data
        observed_tensor = np.array(problem["tensor"])
        mask = np.array(problem["mask"])
        dim1, dim2, dim3 = observed_tensor.shape

        # Unfoldings
        # Mode‑1 unfolding
        X1 = cp.Variable((dim1, dim2 * dim3))
        # Mode‑2 unfolding
        X2 = cp.Variable((dim2, dim1 * dim3))
        # Mode‑3 unfolding
        X3 = cp.Variable((dim3, dim1 * dim2))

        # Build constraints using vectorised operations
        # Mode‑1
        mask1 = mask.reshape(dim1, dim2 * dim3)
        observed1 = observed_tensor.reshape(dim1, dim2 * dim3)
        constr1 = cp.multiply(X1, mask1) == cp.multiply(observed1, mask1)

        # Mode‑2
        mask2 = np.transpose(mask, (1, 0, 2)).reshape(dim2, dim1 * dim3)
        observed2 = np.transpose(observed_tensor, (1, 0, 2)).reshape(dim2, dim1 * dim3)
        constr2 = cp.multiply(X2, mask2) == cp.multiply(observed2, mask2)

        # Mode‑3
        mask3 = np.transpose(mask, (2, 0, 1)).reshape(dim3, dim1 * dim2)
        observed3 = np.transpose(observed_tensor, (2, 0, 1)).reshape(dim3, dim1 * dim2)
        constr3 = cp.multiply(X3, mask3) == cp.multiply(observed3, mask3)

        # Objective: minimize sum of nuclear norms
        objective = cp.Minimize(cp.norm(X1, "nuc") + cp.norm(X2, "nuc") + cp.norm(X3, "nuc"))

        # Solve the problem
        prob = cp.Problem(objective, [constr1, constr2, constr3])
        try:
            prob.solve(solver=cp.SCS, verbose=False, max_iters=5000)
            if prob.status not in {cp.OPTIMAL, cp.OPTIMAL_INACCURATE} or X1.value is None:
                logging.warning(f"Solver status: {prob.status}")
                return {"completed_tensor": []}
            # Fold back the first unfolding to get the completed tensor
            completed_tensor = X1.value.reshape(dim1, dim2, dim3)
            return {"completed_tensor": completed_tensor.tolist()}
        except Exception as e:
            logging.error(f"Solver error: {e}")
            return {"completed_tensor": []}