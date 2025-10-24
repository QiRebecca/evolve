from typing import Any
import numpy as np
import cvxpy as cp

class Solver:
    def solve(self, problem: dict[str, Any], **kwargs) -> Any:
        """
        Solve the rocket landing optimization problem using CVXPY with the SCS solver.
        """
        # Extract problem parameters
        p0 = np.array(problem["p0"])
        v0 = np.array(problem["v0"])
        p_target = np.array(problem["p_target"])
        g = float(problem["g"])
        m = float(problem["m"])
        h = float(problem["h"])
        K = int(problem["K"])
        F_max = float(problem["F_max"])
        gamma = float(problem["gamma"])

        # Variables
        V = cp.Variable((K + 1, 3))  # Velocity
        P = cp.Variable((K + 1, 3))  # Position
        F = cp.Variable((K, 3))      # Thrust

        # Constraints
        constraints = []

        # Initial conditions
        constraints.append(V[0] == v0)
        constraints.append(P[0] == p0)

        # Terminal conditions
        constraints.append(V[K] == np.zeros(3))  # Zero final velocity
        constraints.append(P[K] == p_target)    # Target position

        # Height constraint (always positive)
        constraints.append(P[:, 2] >= 0)

        # Dynamics for velocity
        constraints.append(V[1:, :2] == V[:-1, :2] + h * (F[:, :2] / m))
        constraints.append(V[1:, 2] == V[:-1, 2] + h * (F[:, 2] / m - g))

        # Dynamics for position
        constraints.append(P[1:] == P[:-1] + h / 2 * (V[:-1] + V[1:]))

        # Maximum thrust constraint
        constraints.append(cp.norm(F, 2, axis=1) <= F_max)

        # Objective: minimize fuel consumption
        fuel_consumption = gamma * cp.sum(cp.norm(F, axis=1))
        objective = cp.Minimize(fuel_consumption)

        # Solve the problem using SCS solver
        prob = cp.Problem(objective, constraints)
        try:
            prob.solve(
                solver=cp.SCS,
                verbose=False,
                max_iters=5000,
                eps=1e-5,
                warm_start=True
            )
        except cp.SolverError:
            return {"position": [], "velocity": [], "thrust": [], "fuel_consumption": None}
        except Exception:
            return {"position": [], "velocity": [], "thrust": [], "fuel_consumption": None}

        if prob.status not in {cp.OPTIMAL, cp.OPTIMAL_INACCURATE} or P.value is None:
            return {"position": [], "velocity": [], "thrust": [], "fuel_consumption": None}

        # Return solution
        return {
            "position": P.value.tolist(),
            "velocity": V.value.tolist(),
            "thrust": F.value.tolist(),
            "fuel_consumption": float(prob.value),
        }