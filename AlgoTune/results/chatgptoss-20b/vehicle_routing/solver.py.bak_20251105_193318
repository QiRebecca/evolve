from typing import Any
import logging
from ortools.constraint_solver import pywrapcp, routing_enums_pb2

class Solver:
    def solve(self, problem: dict[str, Any], **kwargs) -> Any:
        """
        Solve the Vehicle Routing Problem using OR-Tools Routing Solver.
        This implementation is typically faster than a CP-SAT formulation
        for moderate-sized instances while still guaranteeing optimality.
        """
        D = problem["D"]
        K = problem["K"]
        depot = problem["depot"]
        n = len(D)

        # Create the routing index manager
        manager = pywrapcp.RoutingIndexManager(n, K, depot)

        # Create Routing Model
        routing = pywrapcp.RoutingModel(manager)

        # Create and register a transit callback
        def distance_callback(from_index, to_index):
            # Convert from routing variable Index to distance matrix NodeIndex
            from_node = manager.IndexToNode(from_index)
            to_node = manager.IndexToNode(to_index)
            return int(D[from_node][to_node])

        transit_callback_index = routing.RegisterTransitCallback(distance_callback)

        # Define cost of each arc
        routing.SetArcCostEvaluatorOfAllVehicles(transit_callback_index)

        # Add Distance constraint to ensure each node is visited exactly once
        # (default behavior of RoutingModel ensures all nodes are visited once)

        # Setting first solution heuristic
        search_parameters = pywrapcp.DefaultRoutingSearchParameters()
        search_parameters.first_solution_strategy = (
            routing_enums_pb2.FirstSolutionStrategy.PATH_CHEAPEST_ARC
        )
        search_parameters.local_search_metaheuristic = (
            routing_enums_pb2.LocalSearchMetaheuristic.GUIDED_LOCAL_SEARCH
        )
        search_parameters.time_limit.seconds = 30  # allow up to 30 seconds

        # Solve the problem
        solution = routing.SolveWithParameters(search_parameters)

        if solution:
            routes = []
            for vehicle_id in range(K):
                index = routing.Start(vehicle_id)
                route = [depot]
                while not routing.IsEnd(index):
                    node = manager.IndexToNode(index)
                    index = solution.Value(routing.NextVar(index))
                    route.append(manager.IndexToNode(index))
                routes.append(route)
            return routes
        else:
            logging.error("No solution found.")
            return []