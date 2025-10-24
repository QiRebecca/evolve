from typing import Any
import scipy.fft

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the N-dimensional DCT Type I using scipy's fast FFT implementation.
        """
        # scipy.fft.dctn is typically faster than scipy.fftpack.dctn
        return scipy.fft.dctn(problem, type=1)