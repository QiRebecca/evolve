from typing import Any
import numpy as np
import scipy.sparse

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Compute the graph Laplacian (standard or normalized) from a CSR representation.
        Returns a dictionary with CSR components of the Laplacian matrix.
        """
        try:
            data = np.array(problem["data"], dtype=float)
            indices = np.array(problem["indices"], dtype=int)
            indptr = np.array(problem["indptr"], dtype=int)
            shape = tuple(problem["shape"])
            normed = problem["normed"]
        except Exception:
            return {
                "laplacian": {
                    "data": [],
                    "indices": [],
                    "indptr": [],
                    "shape": problem.get("shape", (0, 0)),
                }
            }

        n = shape[0]
        try:
            deg = np.diff(indptr).astype(float)

            if not normed:
                # Standard combinatorial Laplacian: L = D - A
                diag_data = deg
                diag_indices = np.arange(n, dtype=int)
                A_csr = scipy.sparse.csr_matrix((data, indices, indptr), shape=shape)
                diag_csr = scipy.sparse.csr_matrix((diag_data, (diag_indices, diag_indices)), shape=shape)
                L_csr = A_csr + diag_csr
                L_csr.eliminate_zeros()
            else:
                # Normalized Laplacian: L = I - D^-1/2 A D^-1/2
                inv_sqrt_deg = np.where(deg > 0, 1.0 / np.sqrt(deg), 0.0)
                row_indices = np.repeat(np.arange(n), np.diff(indptr))
                normed_data = data * inv_sqrt_deg[row_indices] * inv_sqrt_deg[indices]
                A_norm_csr = scipy.sparse.csr_matrix((normed_data, indices, indptr), shape=shape)
                diag = np.where(deg > 0, 1.0, 0.0)
                diag_csr = scipy.sparse.csr_matrix((diag, (np.arange(n), np.arange(n))), shape=shape)
                L_csr = diag_csr - A_norm_csr
                L_csr.eliminate_zeros()

            solution = {
                "laplacian": {
                    "data": L_csr.data.tolist(),
                    "indices": L_csr.indices.tolist(),
                    "indptr": L_csr.indptr.tolist(),
                    "shape": L_csr.shape,
                }
            }
            return solution
        except Exception:
            return {
                "laplacian": {
                    "data": [],
                    "indices": [],
                    "indptr": [],
                    "shape": shape,
                }
            }