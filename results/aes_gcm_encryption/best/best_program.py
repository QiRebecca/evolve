from functools import lru_cache
from typing import Any, Dict

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

# Accepted AES key lengths in bytes
_AES_KEY_SIZES = {16, 24, 32}
_GCM_TAG_SIZE = 16  # bytes


@lru_cache(maxsize=256)
def _get_cipher(key: bytes) -> AESGCM:
    """
    Return a cached AESGCM object for the given key to avoid the
    overhead of repeatedly constructing identical cipher instances.
    """
    # Convert to immutable bytes to ensure hashability even if a bytearray is passed
    return AESGCM(bytes(key))


class Solver:
    """
    Fast AES-GCM encryption solver.

    The evaluate harness calls `solve(problem)` where `problem` is a dict with:
        key: bytes  (16/24/32 bytes)
        nonce: bytes  (12 bytes typical)
        plaintext: bytes
        associated_data: bytes or None
    The method must return {'ciphertext': bytes, 'tag': bytes}
    """

    __slots__ = ()  # prevent per-instance __dict__ creation

    def solve(self, problem: Dict[str, Any], **kwargs) -> Dict[str, bytes]:
        # Fast local variable lookups
        key: bytes = problem["key"]
        nonce: bytes = problem["nonce"]
        plaintext: bytes = problem["plaintext"]
        aad: bytes | None = problem.get("associated_data", None)

        # Quick key length validation (raises early on misuse)
        if len(key) not in _AES_KEY_SIZES:
            raise ValueError("Unsupported AES key length.")

        # Re-use AESGCM objects for identical keys to cut instantiation cost
        aesgcm = _get_cipher(key)

        # Passing None instead of empty bytes avoids extra work inside cryptography
        if not aad:
            aad = None

        ct_and_tag = aesgcm.encrypt(nonce, plaintext, aad)

        # Split ciphertext and tag (last 16 bytes)
        ciphertext = ct_and_tag[:-_GCM_TAG_SIZE]
        tag = ct_and_tag[-_GCM_TAG_SIZE:]

        return {"ciphertext": ciphertext, "tag": tag}