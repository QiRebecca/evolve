from typing import Any
import numpy as np
from scipy.optimize import linprog

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the battery scheduling problem using SciPy linprog (Highs solver).
        This implementation formulates the problem as a linear program with
        variables: q (state of charge), c_in (charging rate), c_out (discharging rate).
        """
        # Extract problem parameters
        T = int(problem["T"])
        p = np.array(problem["p"], dtype=float)
        u = np.array(problem["u"], dtype=float)
        battery = problem["batteries"][0]  # single battery

        Q = float(battery["Q"])
        C = float(battery["C"])
        D = float(battery["D"])
        eta = float(battery["efficiency"])

        # Number of variables: q, c_in, c_out
        n_vars = 3 * T

        # Objective: minimize p @ c = p @ (c_in - c_out)
        c_obj = np.zeros(n_vars)
        c_obj[T:2*T] = p          # coefficients for c_in
        c_obj[2*T:] = -p          # coefficients for c_out

        # Bounds for variables
        bounds = []
        # q bounds
        for _ in range(T):
            bounds.append((0.0, Q))
        # c_in bounds
        for _ in range(T):
            bounds.append((0.0, C))
        # c_out bounds
        for _ in range(T):
            bounds.append((0.0, D))

        # Equality constraints: battery dynamics and cyclic constraint
        A_eq = np.zeros((T, n_vars))
        b_eq = np.zeros(T)

        # Dynamics for t = 0..T-2
        for t in range(T - 1):
            A_eq[t, t] = -1.0          # -q[t]
            A_eq[t, t + 1] = 1.0       # +q[t+1]
            A_eq[t, T + t] = -eta      # -eta * c_in[t]
            A_eq[t, 2*T + t] = 1.0 / eta  # + (1/eta) * c_out[t]
            b_eq[t] = 0.0

        # Cyclic constraint
        t = T - 1
        A_eq[t, 0] = -1.0            # -q[0]
        A_eq[t, t] = 1.0             # +q[T-1]
        A_eq[t, T + t] = -eta        # -eta * c_in[T-1]
        A_eq[t, 2*T + t] = 1.0 / eta  # + (1/eta) * c_out[T-1]
        b_eq[t] = 0.0

        # Inequality constraints: no power back to grid (u + c >= 0)
        A_ub = np.zeros((T, n_vars))
        b_ub = np.zeros(T)
        for t in range(T):
            A_ub[t, T + t] = -1.0   # -c_in[t]
            A_ub[t, 2*T + t] = 1.0  # +c_out[t]
            b_ub[t] = u[t]          # <= u[t]

        # Solve linear program
        res = linprog(
            c=c_obj,
            A_ub=A_ub,
            b_ub=b_ub,
            A_eq=A_eq,
            b_eq=b_eq,
            bounds=bounds,
            method="highs",
            options={"presolve": True}
        )

        status = res.message if res.success else "infeasible"
        optimal = res.success

        if not optimal:
            return {
                "status": status,
                "optimal": False,
                "error": res.message
            }

        # Extract solution
        x = res.x
        q = x[0:T]
        c_in = x[T:2*T]
        c_out = x[2*T:3*T]
        c = c_in - c_out

        cost_without_battery = float(p @ u)
        cost_with_battery = cost_without_battery + float(p @ c)
        savings = cost_without_battery - cost_with_battery

        result = {
            "status": status,
            "optimal": True,
            "battery_results": [
                {
                    "q": q.tolist(),
                    "c": c.tolist(),
                    "c_in": c_in.tolist(),
                    "c_out": c_out.tolist(),
                    "cost": cost_with_battery,
                }
            ],
            "total_charging": c.tolist(),
            "cost_without_battery": cost_without_battery,
            "cost_with_battery": cost_with_battery,
            "savings": savings,
            "savings_percent": float(100 * savings / cost_without_battery),
        }

        return result