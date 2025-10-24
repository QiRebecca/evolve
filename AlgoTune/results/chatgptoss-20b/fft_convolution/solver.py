from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the convolution of two signals using the Fast Fourier Transform (FFT) approach.
        The result is returned as a list under the key 'convolution'.
        """
        # Extract signals and mode
        signal_x = np.array(problem.get("signal_x", []), dtype=float)
        signal_y = np.array(problem.get("signal_y", []), dtype=float)
        mode = problem.get("mode", "full")

        # Handle empty inputs
        if signal_x.size == 0 or signal_y.size == 0:
            return {"convolution": []}

        len_x = signal_x.size
        len_y = signal_y.size

        # Full convolution length
        n_full = len_x + len_y - 1

        # Compute FFTs with length n_full
        X = np.fft.fft(signal_x, n_full)
        Y = np.fft.fft(signal_y, n_full)
        Z = np.fft.ifft(X * Y).real

        # Determine result based on mode
        if mode == "full":
            result = Z
        elif mode == "same":
            # Length of the output for 'same' mode
            out_len = max(len_x, len_y)
            start = (n_full - out_len) // 2
            result = Z[start:start + out_len]
        elif mode == "valid":
            # Length of the output for 'valid' mode
            if len_x >= len_y:
                start = len_y - 1
                out_len = len_x - len_y + 1
            else:
                start = len_x - 1
                out_len = len_y - len_x + 1
            result = Z[start:start + out_len]
        else:
            # Unsupported mode; return empty result
            result = np.array([], dtype=float)

        # Convert to list for compatibility with the validation function
        return {"convolution": result.tolist()}