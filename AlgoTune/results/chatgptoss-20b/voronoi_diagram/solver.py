from typing import Any
import numpy as np
from scipy.spatial import Voronoi

class Solver:
    def solve(self, problem: dict[str, Any], **kwargs) -> Any:
        points = problem["points"]
        vor = Voronoi(points)
        solution = {
            "vertices": vor.vertices.tolist(),
            "regions": [list(region) for region in vor.regions],
            "point_region": np.arange(len(points)),
            "ridge_points": vor.ridge_points.tolist(),
            "ridge_vertices": vor.ridge_vertices.tolist(),
        }
        solution["regions"] = [solution["regions"][idx] for idx in vor.point_region]
        return solution