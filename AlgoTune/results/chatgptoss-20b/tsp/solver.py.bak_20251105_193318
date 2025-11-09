from typing import Any
from ortools.constraint_solver import pywrapcp, routing_enums_pb2

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the TSP problem using OR-Tools Routing Solver.

        :param problem: Distance matrix as a list of lists.
        :param kwargs: Optional parameters, e.g. time_limit (seconds).
        :return: A list representing the optimal tour, starting and ending at city 0.
        """
        n = len(problem)

        if n <= 1:
            return [0, 0]

        # Create the routing index manager and model
        manager = pywrapcp.RoutingIndexManager(n, 1, 0)
        routing = pywrapcp.RoutingModel(manager)

        # Distance callback
        def distance_callback(from_index, to_index):
            from_node = manager.IndexToNode(from_index)
            to_node = manager.IndexToNode(to_index)
            return problem[from_node][to_node]

        transit_callback_index = routing.RegisterTransitCallback(distance_callback)
        routing.SetArcCostEvaluatorOfAllVehicles(transit_callback_index)

        # No capacity constraints for TSP
        # Set search parameters
        search_parameters = pywrapcp.DefaultRoutingSearchParameters()
        search_parameters.first_solution_strategy = (
            routing_enums_pb2.FirstSolutionStrategy.PATH_CHEAPEST_ARC)
        search_parameters.local_search_metaheuristic = (
            routing_enums_pb2.LocalSearchMetaheuristic.GUIDED_LOCAL_SEARCH)
        search_parameters.time_limit.seconds = kwargs.get('time_limit', 60)
        search_parameters.use_cp = True  # use CP-SAT for exact solution

        # Solve the problem
        solution = routing.SolveWithParameters(search_parameters)

        if solution:
            index = routing.Start(0)
            path = []
            while not routing.IsEnd(index):
                node = manager.IndexToNode(index)
                path.append(node)
                index = solution.Value(routing.NextVar(index))
            # Append the end node (depot)
            path.append(manager.IndexToNode(index))
            return path
        else:
            return []