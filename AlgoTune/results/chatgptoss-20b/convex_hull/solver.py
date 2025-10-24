from typing import Any
import numpy as np

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the convex hull of a set of 2D points using the monotone chain algorithm.
        Returns hull vertices indices and hull points in counter-clockwise order.
        """
        points = np.array(problem["points"])
        n = len(points)
        if n == 0:
            return {"hull_vertices": [], "hull_points": []}
        if n == 1:
            return {"hull_vertices": [0], "hull_points": points.tolist()}

        # Create array of original indices
        idx = np.arange(n)

        # Sort points by x, then y
        order = np.lexsort((points[:, 1], points[:, 0]))
        sorted_points = points[order]
        sorted_idx = idx[order]

        def cross(o, a, b):
            return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

        # Build lower hull
        lower_idx = []
        for p, i in zip(sorted_points, sorted_idx):
            while len(lower_idx) >= 2:
                o = sorted_points[lower_idx[-2]]
                a = sorted_points[lower_idx[-1]]
                if cross(o, a, p) <= 0:
                    lower_idx.pop()
                else:
                    break
            lower_idx.append(i)

        # Build upper hull
        upper_idx = []
        for p, i in zip(reversed(sorted_points), reversed(sorted_idx)):
            while len(upper_idx) >= 2:
                o = sorted_points[upper_idx[-2]]
                a = sorted_points[upper_idx[-1]]
                if cross(o, a, p) <= 0:
                    upper_idx.pop()
                else:
                    break
            upper_idx.append(i)

        # Concatenate lower and upper to get full hull, excluding duplicate endpoints
        hull_idx = lower_idx[:-1] + upper_idx[:-1]
        hull_points = points[hull_idx].tolist()

        return {"hull_vertices": hull_idx, "hull_points": hull_points}