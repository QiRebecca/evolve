from typing import Any
import base64
import logging

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """Encode the plaintext using the Base64 algorithm."""
        plaintext = problem.get("plaintext")

        if not isinstance(plaintext, (bytes, bytearray)):
            raise TypeError("The 'plaintext' field must be bytes or bytearray.")

        try:
            encoded_data = base64.b64encode(plaintext)
            return {"encoded_data": encoded_data}
        except Exception as e:
            logging.error(f"Error during Base64 encoding in solve: {e}")
            raise