from typing import Any
from ortools.sat.python import cp_model

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the Job Shop Scheduling Problem (JSSP) using OR-Tools CP-SAT solver.
        The solver constructs interval variables for each operation, enforces
        precedence constraints within jobs, no-overlap constraints on machines,
        and minimizes the makespan.  The solution is returned as a list of
        start times for each operation in each job.
        """
        M = problem["num_machines"]
        jobs_data = problem["jobs"]

        # Compute a safe horizon: sum of all durations
        horizon = sum(d for job in jobs_data for _, d in job)

        model = cp_model.CpModel()

        # Store interval variables and map machine to its intervals
        all_tasks = {}  # (job_id, op_id) -> (start, end, duration)
        machine_to_intervals = {m: [] for m in range(M)}

        for j, job in enumerate(jobs_data):
            for k, (m, p) in enumerate(job):
                suffix = f"_{j}_{k}"
                start = model.NewIntVar(0, horizon, f"start{suffix}")
                end = model.NewIntVar(0, horizon, f"end{suffix}")
                interval = model.NewIntervalVar(start, p, end, f"interval{suffix}")
                all_tasks[(j, k)] = (start, end, p)
                machine_to_intervals[m].append(interval)

                # Precedence constraint within the same job
                if k > 0:
                    prev_end = all_tasks[(j, k - 1)][1]
                    model.Add(start >= prev_end)

        # No-overlap constraints on each machine
        for m in range(M):
            model.AddNoOverlap(machine_to_intervals[m])

        # Makespan objective
        makespan = model.NewIntVar(0, horizon, "makespan")
        last_ends = []
        for job_id, job in enumerate(jobs_data):
            _, end_var, _ = all_tasks[(job_id, len(job) - 1)]
            last_ends.append(end_var)
        model.AddMaxEquality(makespan, last_ends)
        model.Minimize(makespan)

        # Solver configuration for speed
        solver = cp_model.CpSolver()
        solver.parameters.num_search_workers = 8
        solver.parameters.cp_model_presolve = True
        solver.parameters.cp_model_probing_level = 0
        solver.parameters.cp_model_use_sat = True

        status = solver.Solve(model)

        if status == cp_model.OPTIMAL:
            solution = []
            for j, job in enumerate(jobs_data):
                starts = []
                for k, _ in enumerate(job):
                    starts.append(int(solver.Value(all_tasks[(j, k)][0])))
                solution.append(starts)
            return solution
        else:
            # If no optimal solution is found, return empty.
            return []
