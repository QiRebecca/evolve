from typing import Any

class Solver:
    def __init__(self):
        self.order = 3
        self.mode = 'constant'
        self.cval = 0.0

    def solve(self, problem, **kwargs) -> Any:
        import scipy.ndimage
        image = problem["image"]
        shift_vector = problem["shift"]
        try:
            shifted_image = scipy.ndimage.shift(
                image,
                shift_vector,
                order=self.order,
                mode=self.mode,
                cval=self.cval
            )
        except Exception:
            return {"shifted_image": []}
        return {"shifted_image": shifted_image}