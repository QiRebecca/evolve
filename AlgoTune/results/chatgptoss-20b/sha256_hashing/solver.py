from typing import Any
import hashlib

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        plaintext = problem["plaintext"]
        hash_value = hashlib.sha256(plaintext).digest()
        return {"digest": hash_value}