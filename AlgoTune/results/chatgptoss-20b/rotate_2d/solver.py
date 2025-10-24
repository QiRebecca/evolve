from typing import Any
import numpy as np
import scipy.ndimage

class Solver:
    reshape: bool = False
    order: int = 3
    mode: str = 'constant'

    def solve(self, problem, **kwargs) -> Any:
        image = problem["image"]
        angle = problem["angle"]
        rotated_image = scipy.ndimage.rotate(
            image, angle, reshape=self.reshape, order=self.order, mode=self.mode
        )
        return {"rotated_image": rotated_image}