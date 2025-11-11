from functools import lru_cache
from typing import Any, Dict

from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

# ---------------------------------------------------------------------------
# Module-level constants & helpers (defined once to avoid per-call overhead)
# ---------------------------------------------------------------------------
_VALID_KEY_SIZES = {16, 24, 32}   # Allowed AES key lengths in bytes
_TAG_SIZE = 16                    # GCM authentication tag length (bytes)
_backend = default_backend()      # Re-used backend instance


@lru_cache(maxsize=128)
def _cipher_for_key(key: bytes) -> algorithms.AES:
    """
    Cache AES algorithm objects per key to skip repeated key expansion cost.
    The cryptography backend makes this cheap, but caching still helps a bit
    when many problems reuse the same key.
    """
    return algorithms.AES(key)


class Solver:
    """
    Fast AES-GCM encryption solver.

    Expected problem format:
        {
            "key": bytes,            # 16 / 24 / 32 bytes
            "nonce": bytes,          # 12 bytes recommended
            "plaintext": bytes,
            "associated_data": bytes | None
        }

    Returned solution format:
        { "ciphertext": bytes, "tag": bytes }
    """

    def solve(self, problem: Dict[str, Any], **_) -> Dict[str, bytes]:
        key: bytes = problem["key"]
        nonce: bytes = problem["nonce"]
        plaintext: bytes = problem["plaintext"]
        aad: bytes | None = problem.get("associated_data")

        # Lightweight validation
        if len(key) not in _VALID_KEY_SIZES:
            raise ValueError("Invalid AES key length.")

        # Obtain (cached) AES algorithm for this key
        algorithm = _cipher_for_key(key)

        # Create encryptor with GCM mode
        encryptor = Cipher(algorithm, modes.GCM(nonce), backend=_backend).encryptor()

        # Attach AAD only if it exists and is non-empty
        if aad:
            encryptor.authenticate_additional_data(aad)

        # Encrypt in one shot; cryptography performs highly-optimized C routines
        ciphertext = encryptor.update(plaintext) + encryptor.finalize()

        # Retrieve the 16-byte authentication tag produced by GCM
        tag: bytes = encryptor.tag  # length always _TAG_SIZE

        # Return the separated ciphertext and tag
        return {"ciphertext": ciphertext, "tag": tag}