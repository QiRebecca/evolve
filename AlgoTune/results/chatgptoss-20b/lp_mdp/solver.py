from typing import Any
import numpy as np

class Solver:
    def solve(self, problem: dict[str, Any], **kwargs) -> Any:
        """
        Solve the discounted MDP using policy iteration.
        This implementation is faster than the baseline LP approach
        while producing the same optimal value function and policy.
        """
        num_states = problem["num_states"]
        num_actions = problem["num_actions"]
        gamma = problem["discount"]

        transitions = np.array(problem["transitions"], dtype=np.float64)  # shape (S, A, S)
        rewards = np.array(problem["rewards"], dtype=np.float64)          # shape (S, A, S)

        # Initial policy: choose action 0 for all states
        policy = np.zeros(num_states, dtype=int)

        # Policy iteration loop
        while True:
            # Build transition matrix and reward vector for current policy
            P_pi = transitions[np.arange(num_states), policy, :]  # shape (S, S)
            R_pi = np.sum(transitions[np.arange(num_states), policy, :] *
                          rewards[np.arange(num_states), policy, :], axis=1)  # shape (S,)

            # Solve (I - gamma * P_pi) * V = R_pi
            A = np.eye(num_states, dtype=np.float64) - gamma * P_pi
            V = np.linalg.solve(A, R_pi)

            # Compute Q-values for all state-action pairs
            # Q[s,a] = sum_{s'} P(s'|s,a) * (R(s,a,s') + gamma * V[s'])
            Q = np.sum(transitions * (rewards + gamma * V[None, None, :]), axis=2)  # shape (S, A)

            # Determine new policy: for each state, pick first action that achieves max Q within tolerance
            max_Q = np.max(Q, axis=1)
            # Boolean mask where Q is within 1e-8 of the maximum
            mask = Q >= (max_Q[:, None] - 1e-8)
            new_policy = np.argmax(mask, axis=1)

            # Check for convergence
            if np.array_equal(policy, new_policy):
                break
            policy = new_policy

        # Convert results to Python lists
        value_function = V.tolist()
        policy_list = policy.tolist()

        return {"value_function": value_function, "policy": policy_list}