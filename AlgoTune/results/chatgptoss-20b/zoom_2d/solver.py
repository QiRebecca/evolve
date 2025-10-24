from typing import Any
import numpy as np
import scipy.ndimage

class Solver:
    def __init__(self):
        self.order = 3
        self.mode = 'constant'

    def solve(self, problem, **kwargs) -> Any:
        """
        Zoom a 2D image using scipy.ndimage.zoom with cubic spline interpolation.
        """
        image = problem.get("image")
        zoom_factor = problem.get("zoom_factor")

        if image is None or zoom_factor is None:
            return {"zoomed_image": []}

        try:
            img_array = np.asarray(image, dtype=float)
            zoomed = scipy.ndimage.zoom(img_array, zoom_factor, order=self.order, mode=self.mode)
        except Exception:
            return {"zoomed_image": []}

        return {"zoomed_image": zoomed.tolist()}