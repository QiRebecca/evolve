from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the 2D correlation of arrays a and b using "full" mode and "fill" boundary
        via FFT-based convolution for speed.
        """
        a, b = problem
        a_shape = a.shape
        b_shape = b.shape
        out_shape = (a_shape[0] + b_shape[0] - 1, a_shape[1] + b_shape[1] - 1)

        # Zero-pad a to output size
        a_padded = np.zeros(out_shape, dtype=np.float64)
        a_padded[:a_shape[0], :a_shape[1]] = a

        # Flip b for correlation and zero-pad
        b_flipped = np.flipud(np.fliplr(b))
        b_padded = np.zeros(out_shape, dtype=np.float64)
        b_padded[:b_shape[0], :b_shape[1]] = b_flipped

        # FFT-based convolution (correlation)
        A = np.fft.fft2(a_padded, s=out_shape)
        B = np.fft.fft2(b_padded, s=out_shape)
        result = np.fft.ifft2(A * B).real

        return result