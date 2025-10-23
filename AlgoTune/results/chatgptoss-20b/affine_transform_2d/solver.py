import logging
from typing import Any

import numpy as np
import scipy.ndimage


class Solver:
    def __init__(self):
        # Parameters matching the baseline configuration
        self.order = 3          # Cubic spline interpolation
        self.mode = "constant"  # Pad with zeros outside the input
        self.cval = 0.0         # Constant value for padding

    def solve(self, problem: dict[str, Any], **kwargs) -> Any:
        """
        Apply a 2D affine transformation to the input image using
        scipy.ndimage.affine_transform with cubic spline interpolation
        and zero padding.

        Parameters
        ----------
        problem : dict
            Dictionary containing:
                - "image": 2D array-like of shape (n, n) with float values.
                - "matrix": 2x3 array-like defining the affine transformation.

        Returns
        -------
        dict
            Dictionary with key "transformed_image" containing the
            transformed image as a nested list of floats.
        """
        image = problem.get("image")
        matrix = problem.get("matrix")

        if image is None or matrix is None:
            logging.error("Missing 'image' or 'matrix' in problem input.")
            return {"transformed_image": []}

        try:
            # Convert inputs to numpy arrays to ensure correct dtype
            image_arr = np.asarray(image, dtype=float)
            matrix_arr = np.asarray(matrix, dtype=float)

            transformed = scipy.ndimage.affine_transform(
                image_arr,
                matrix_arr,
                order=self.order,
                mode=self.mode,
                cval=self.cval,
            )
        except Exception as exc:
            logging.error(f"Affine transformation failed: {exc}")
            return {"transformed_image": []}

        # Convert the resulting array back to a nested list for consistency
        return {"transformed_image": transformed.tolist()}