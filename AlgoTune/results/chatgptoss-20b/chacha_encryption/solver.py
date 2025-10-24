from typing import Any
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

CHACHA_KEY_SIZE = 32
POLY1305_TAG_SIZE = 16

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        key = problem["key"]
        nonce = problem["nonce"]
        plaintext = problem["plaintext"]
        associated_data = problem.get("associated_data", None)

        if len(key) != CHACHA_KEY_SIZE:
            raise ValueError(f"Invalid key size: {len(key)}. Must be {CHACHA_KEY_SIZE}.")

        chacha = ChaCha20Poly1305(key)
        ciphertext = chacha.encrypt(nonce, plaintext, associated_data)

        if len(ciphertext) < POLY1305_TAG_SIZE:
            raise ValueError("Encrypted output is shorter than the expected tag size.")

        actual_ciphertext = ciphertext[:-POLY1305_TAG_SIZE]
        tag = ciphertext[-POLY1305_TAG_SIZE:]

        return {"ciphertext": actual_ciphertext, "tag": tag}