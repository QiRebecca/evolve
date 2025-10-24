from typing import Any
import gzip

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        plaintext = problem["plaintext"]
        compressed_data = gzip.compress(plaintext, compresslevel=9, mtime=0)
        return {"compressed_data": compressed_data}