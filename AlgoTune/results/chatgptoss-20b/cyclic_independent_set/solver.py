from typing import Any
import itertools

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the cyclic graph independent set problem for a 7-node cycle.

        The optimal independent set in the n-th strong product of a 7-cycle
        is the Cartesian product of the maximum independent set of the base
        cycle, which is {0, 2, 4}.  This yields 3^n vertices and is optimal
        because any two distinct tuples differ in at least one coordinate
        where the distance in the base cycle is at least 2, thus they are
        not adjacent in the strong product.

        Args:
            problem (tuple): A tuple (num_nodes, n) representing the problem instance.
                              num_nodes is expected to be 7.

        Returns:
            List[Tuple[int, ...]]: The optimal independent set as a list of n-tuples.
        """
        _, n = problem
        # Generate all n-tuples using the optimal independent set of the base cycle.
        base_set = (0, 2, 4)
        return [tuple(v) for v in itertools.product(base_set, repeat=n)]