from typing import Any
import numpy as np
import scipy.stats as stats

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """Perform two-sample Kolmogorov-Smirnov test to compute statistic and pvalue."""
        # Convert input lists to numpy arrays
        a = np.asarray(problem["sample1"], dtype=np.float64)
        b = np.asarray(problem["sample2"], dtype=np.float64)
        n1 = a.size
        n2 = b.size

        # Sort the samples
        a_sorted = np.sort(a)
        b_sorted = np.sort(b)

        # Two-pointer merge to compute maximum absolute difference of ECDFs
        i = j = 0
        max_diff = 0.0
        while i < n1 and j < n2:
            # Current empirical CDF values
            cdf_a = (i + 1) / n1
            cdf_b = (j + 1) / n2
            # Update maximum difference
            diff = abs(cdf_a - cdf_b)
            if diff > max_diff:
                max_diff = diff
            # Advance the pointer with the smaller value
            if a_sorted[i] <= b_sorted[j]:
                i += 1
            else:
                j += 1

        # After one array is exhausted, the remaining values in the other array
        # will only increase its CDF towards 1. The difference can only increase
        # when the other CDF is still below 1. We handle this by iterating
        # over the remaining elements.
        while i < n1:
            cdf_a = (i + 1) / n1
            cdf_b = 1.0
            diff = abs(cdf_a - cdf_b)
            if diff > max_diff:
                max_diff = diff
            i += 1
        while j < n2:
            cdf_a = 1.0
            cdf_b = (j + 1) / n2
            diff = abs(cdf_a - cdf_b)
            if diff > max_diff:
                max_diff = diff
            j += 1

        # Compute the p-value using the asymptotic Kolmogorov distribution
        # The effective sample size for the two-sample test
        neff = n1 * n2 / (n1 + n2)
        lambda_val = max_diff * np.sqrt(neff)
        # Use scipy's Kolmogorov-Smirnov distribution for two-sample test
        pvalue = stats.kstwo.sf(lambda_val, n1 + n2)

        return {"statistic": float(max_diff), "pvalue": float(pvalue)}