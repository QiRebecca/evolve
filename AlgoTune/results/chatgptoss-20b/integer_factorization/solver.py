from typing import Any
import random
import math
import sympy

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Factor a composite integer that is the product of two primes using
        Pollard's Rho algorithm with Brent's cycle detection. The algorithm
        is efficient for numbers up to several hundred bits and returns
        the two prime factors in ascending order.
        """
        composite_val = problem.get("composite")
        if composite_val is None:
            raise ValueError("Problem must contain 'composite' key.")
        # Ensure we work with a plain Python int
        try:
            n = int(composite_val)
        except Exception as e:
            raise ValueError(f"Composite value '{composite_val}' cannot be converted to int: {e}")

        if n <= 1:
            raise ValueError("Composite must be greater than 1.")

        # Simple trial division for small factors
        def _trial_division(n):
            small_primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47]
            for p in small_primes:
                if n % p == 0:
                    return p
            return None

        # Miller-Rabin primality test via sympy
        def _is_prime(n):
            return sympy.isprime(n)

        # Pollard's Rho with Brent's cycle detection
        def _pollard_rho(n):
            if n % 2 == 0:
                return 2
            if n % 3 == 0:
                return 3
            # Random seed
            rng = random.SystemRandom()
            while True:
                c = rng.randrange(1, n)
                f = lambda x: (pow(x, 2, n) + c) % n
                x = rng.randrange(0, n)
                y = x
                d = 1
                # Brent's algorithm parameters
                m = 128
                r = 1
                while d == 1:
                    x = y
                    for _ in range(r):
                        y = f(y)
                    k = 0
                    while k < r and d == 1:
                        ys = y
                        for _ in range(min(m, r - k)):
                            y = f(y)
                            d = math.gcd(abs(x - y), n)
                        k += m
                    r <<= 1
                if d == n:
                    continue
                return d

        # Recursive factorization
        def _factor(n):
            if n == 1:
                return []
            if _is_prime(n):
                return [n]
            d = _pollard_rho(n)
            return _factor(d) + _factor(n // d)

        # Attempt trial division first
        small_factor = _trial_division(n)
        if small_factor:
            other = n // small_factor
            if _is_prime(other):
                factors = [small_factor, other]
            else:
                factors = _factor(n)
        else:
            factors = _factor(n)

        if len(factors) != 2:
            raise ValueError(f"Expected 2 prime factors, got {len(factors)}: {factors}")

        p, q = sorted(factors)
        return {"p": p, "q": q}