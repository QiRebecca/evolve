from typing import Any
import numpy as np
from scipy.integrate import solve_ivp

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Solve the N-body gravitational system using a high-order
        explicit integrator (DOP853) with tight tolerances.
        """
        # Extract problem parameters
        t0 = float(problem["t0"])
        t1 = float(problem["t1"])
        y0 = np.array(problem["y0"], dtype=float)
        masses = np.array(problem["masses"], dtype=float)
        eps = float(problem["softening"])
        N = int(problem["num_bodies"])

        # Precompute mass array for broadcasting
        m_j = masses.reshape(1, N, 1)  # shape (1,N,1)

        def rhs(t, y):
            # y shape: (6N,)
            pos = y[:3 * N].reshape(N, 3)  # positions
            vel = y[3 * N:].reshape(N, 3)  # velocities

            # Pairwise position differences: (i,j) -> r_i - r_j
            diff = pos[:, None, :] - pos[None, :, :]  # shape (N,N,3)

            # Distance squared with softening
            dist2 = np.sum(diff ** 2, axis=2) + eps ** 2  # shape (N,N)

            # Inverse distance cubed
            inv_dist3 = 1.0 / np.sqrt(dist2 ** 3)  # shape (N,N)

            # Zero self-interaction
            np.fill_diagonal(inv_dist3, 0.0)

            # Acceleration: sum over j of m_j * (r_j - r_i) / |r_ij|^3
            # Note diff is r_i - r_j, so we use -diff
            acc = -np.sum(m_j * diff * inv_dist3[:, :, None], axis=1)  # shape (N,3)

            # Flatten derivatives: velocities followed by accelerations
            return np.concatenate([vel.ravel(), acc.ravel()])

        # Solve ODE
        sol = solve_ivp(
            rhs,
            (t0, t1),
            y0,
            method="DOP853",
            rtol=1e-9,
            atol=1e-12,
            t_eval=[t1],
            vectorized=False,
        )

        if not sol.success:
            raise RuntimeError(f"Solver failed: {sol.message}")

        # Return final state as list
        return sol.y[:, -1].tolist()