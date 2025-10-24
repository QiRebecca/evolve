from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the 2D convolution of arrays a and b using "full" mode and "fill" boundary
        via FFT for speed. This implementation matches scipy.signal.convolve2d
        for real-valued inputs within a small numerical tolerance.
        """
        a, b = problem
        # Determine the size of the full convolution
        out_shape = (a.shape[0] + b.shape[0] - 1, a.shape[1] + b.shape[1] - 1)
        # Perform FFT-based convolution
        fa = np.fft.fft2(a, out_shape)
        fb = np.fft.fft2(b, out_shape)
        conv = np.fft.ifft2(fa * fb).real
        return conv