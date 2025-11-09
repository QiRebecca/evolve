import hmac
import logging
import os
from typing import Any, Final

from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

# --------------------------------------------------------------------------- #
# Module-level constants & singletons
# --------------------------------------------------------------------------- #
AES_KEY_SIZES: Final = (16, 24, 32)   # Valid AES key lengths
GCM_NONCE_SIZE: Final = 12            # Recommended nonce size for AES-GCM
GCM_TAG_SIZE:  Final = 16             # Authentication tag size (bytes)
_BACKEND = default_backend()          # Cache backend to avoid per-call creation


class Solver:
    """
    Fast AES-GCM encryption solver.

    The evaluation harness supplies a dictionary with:
        key : bytes
        nonce : bytes
        plaintext : bytes
        associated_data : bytes | None

    The solver returns:
        {"ciphertext": bytes, "tag": bytes}
    """

    # Helpers for optional local testing (unused by judge)
    DEFAULT_KEY_SIZE: Final = 16       # AES-128
    DEFAULT_PLAINTEXT_MULT: Final = 1024

    # --------------------------------------------------------------------- #
    # Main entry point
    # --------------------------------------------------------------------- #
    def solve(self, problem: dict[str, Any], **__) -> dict[str, bytes]:
        """
        Encrypt *plaintext* under AES-GCM with given *key* and *nonce*.
        Designed for maximum throughput with minimum Python-side overhead.
        """
        # Fast locals
        key        = problem["key"]
        nonce      = problem["nonce"]
        plaintext  = problem["plaintext"]
        aad        = problem["associated_data"]

        # Quick key-length guard (full validation handled inside OpenSSL)
        if len(key) not in AES_KEY_SIZES:
            raise ValueError(f"Unsupported AES key length {len(key)}.")

        # Initialise cipher context once per call
        encryptor = Cipher(
            algorithms.AES(key),
            modes.GCM(nonce),
            backend=_BACKEND,
        ).encryptor()

        # Feed AAD only when non-empty/non-None (saves a C call)
        if aad:
            encryptor.authenticate_additional_data(aad)

        # ----------------------------------------------------------------- #
        # Zero-copy encryption path: write directly into a pre-allocated buf
        # ----------------------------------------------------------------- #
        buf = bytearray(len(plaintext))
        written = encryptor.update_into(plaintext, buf)
        encryptor.finalize()  # obtains tag on finalize

        # `update_into` must process everything for GCM
        if written != len(plaintext):
            # Fallback (should never fire)
            ciphertext = encryptor.update(plaintext) + encryptor.finalize()
        else:
            ciphertext = bytes(buf)  # single copy into immutable bytes

        return {"ciphertext": ciphertext, "tag": encryptor.tag}

    # --------------------------------------------------------------------- #
    # Validation routine (same semantics as baseline)
    # --------------------------------------------------------------------- #
    def is_solution(self, problem: dict[str, Any], solution: dict[str, bytes] | Any) -> bool:
        if (
            not isinstance(solution, dict)
            or "ciphertext" not in solution
            or "tag" not in solution
            or not isinstance(solution["ciphertext"], (bytes, bytearray))
            or not isinstance(solution["tag"], (bytes, bytearray))
        ):
            logging.error("Solution format invalid.")
            return False

        reference = self.solve(problem)
        return (
            hmac.compare_digest(reference["ciphertext"], solution["ciphertext"])
            and hmac.compare_digest(reference["tag"], solution["tag"])
        )

    # --------------------------------------------------------------------- #
    # Optional generator for local experimentation
    # --------------------------------------------------------------------- #
    def generate_problem(self, n: int, random_seed: int = 1) -> dict[str, Any]:
        key       = os.urandom(self.DEFAULT_KEY_SIZE)
        nonce     = os.urandom(GCM_NONCE_SIZE)
        plaintext = os.urandom(max(1, n * self.DEFAULT_PLAINTEXT_MULT))
        aad       = os.urandom(32) if n % 2 == 0 else b""
        return {
            "key": key,
            "nonce": nonce,
            "plaintext": plaintext,
            "associated_data": aad,
        }