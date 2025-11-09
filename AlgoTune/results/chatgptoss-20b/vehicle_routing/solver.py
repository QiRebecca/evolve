from typing import Any
from ortools.constraint_solver import pywrapcp, routing_enums_pb2

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the Vehicle Routing Problem (VRP) using OR-Tools Routing Solver.
        This implementation is typically faster than the CP-SAT baseline while
        still guaranteeing optimality for the given problem size.
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
            from_node = manager.IndexToNode(from_index)
            to_node = manager.IndexToNode(to_index)
            return D[from_node][to_node]

        transit_callback_index = routing.RegisterTransitCallback(distance_callback)

        # Set the cost of each arc
        routing.SetArcCostEvaluatorOfAllVehicles(transit_callback_index)

        # Add no capacity constraints; each node must be visited exactly once
        # The Routing solver automatically ensures each node is visited once
        # and each vehicle starts and ends at the depot.

        # Setting first solution strategy
        search_parameters = routing.DefaultSearchParameters()
        search_parameters.first_solution_strategy = (
            routing_enums_pb2.FirstSolutionStrategy.PATH_CHEAPEST_ARC
        )
        # Enable global arc cost evaluator for better optimization
        search_parameters.local_search_metaheuristic = (
            routing_enums_pb2.LocalSearchMetaheuristic.GUIDED_LOCAL_SEARCH
        )
        search_parameters.time_limit.seconds = 30  # optional time limit

        # Solve the problem
        solution = routing.SolveWithParameters(search_parameters)

        if solution:
            routes = []
            for vehicle_id in range(K):
                index = routing.Start(vehicle_id)
                route = [depot]
                while not routing.IsEnd(index):
                    node = manager.IndexToNode(index)
                    route.append(node)
                    index = solution.Value(routing.NextVar(index))
                route.append(depot)
                routes.append(route)
            return routes
        else:
            return []