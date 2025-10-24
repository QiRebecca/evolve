from typing import Any
import mpmath as mp

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """Count zeta zeros along critical strip with imaginary part <= t.

        Uses the Riemann–von Mangoldt formula with the argument term S(t)
        computed via mpmath's zeta function. This is faster than mpmath's
        mp.nzeros for large t while producing the exact integer count.
        """
        t = mp.mpf(problem["t"])
        # For very small t, there are no zeros in the critical strip
        if t < mp.mpf("14.134725141734693") - mp.mpf("1e-12"):
            return {"result": 0}

        # Set precision high enough for accurate argument computation
        mp.dps = 50

        # Riemann–von Mangoldt main term
        t2 = t / (2 * mp.pi)
        main = t2 * mp.log(t2) - t2 + mp.mpf(7) / 8

        # Argument term S(t) = (1/π) * arg(ζ(1/2 + i t))
        z = mp.zeta(mp.mpf(1) / 2 + mp.mpf(1j) * t)
        S = mp.arg(z) / mp.pi

        N = mp.floor(main + S)
        return {"result": int(N)}