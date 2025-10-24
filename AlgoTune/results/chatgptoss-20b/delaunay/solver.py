from typing import Any
import numpy as np
from scipy.spatial import Delaunay

class Solver:
    def _canonical_simplices(self, simplices: np.ndarray) -> list[list[int]]:
        # sort each simplex's indices
        sorted_simplices = np.sort(simplices, axis=1)
        # sort rows lexicographically
        sorted_simplices = sorted_simplices[np.lexsort((sorted_simplices[:,2], sorted_simplices[:,1], sorted_simplices[:,0]))]
        return sorted_simplices.tolist()

    def _canonical_edges(self, edges: np.ndarray) -> list[list[int]]:
        # sort each edge's indices
        sorted_edges = np.sort(edges, axis=1)
        # sort rows lexicographically
        sorted_edges = sorted_edges[np.lexsort((sorted_edges[:,1], sorted_edges[:,0]))]
        return sorted_edges.tolist()

    def solve(self, problem: dict[str, Any], **kwargs) -> Any:
        pts = np.asarray(problem["points"])
        tri = Delaunay(pts)
        simplices = tri.simplices
        convex_hull = tri.convex_hull
        result = {
            "simplices": self._canonical_simplices(simplices),
            "convex_hull": self._canonical_edges(convex_hull),
        }
        return result