from typing import Any, Dict, Optional

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

# Accepted AES key sizes (bytes) and tag length
_AES_KEY_SIZES = {16, 24, 32}
_TAG_LEN = 16  # 128-bit GCM tag


class _AesGcmCache:
    """
    Very small cache for AESGCM objects keyed by key bytes.
    Since AESGCM objects are lightweight but their creation still incurs
    some overhead (key schedule), caching helps when the same key is reused.
    Capacity is intentionally limited to keep memory usage tiny.
    """
    __slots__ = ("_cache", "_order", "_capacity")

    def __init__(self, capacity: int = 8):
        self._cache: Dict[bytes, AESGCM] = {}
        self._order: list[bytes] = []
        self._capacity = capacity

    def get(self, key: bytes) -> AESGCM:
        aes = self._cache.get(key)
        if aes is not None:
            return aes
        # Create new and cache
        aes = AESGCM(key)
        self._cache[key] = aes
        self._order.append(key)
        if len(self._order) > self._capacity:
            # Evict the oldest key to keep memory bounded
            old = self._order.pop(0)
            self._cache.pop(old, None)
        return aes


class Solver:
    """
    Fast AES-GCM encryption solver.

    Given a dict with 'key', 'nonce', 'plaintext', and 'associated_data',
    returns {'ciphertext': <bytes>, 'tag': <bytes>} exactly matching the
    reference implementation but with reduced overhead.
    """

    # Shared AESGCM cache across all solver instances to maximise reuse
    _aes_cache = _AesGcmCache()

    def solve(self, problem: Dict[str, Any], **kwargs) -> Dict[str, bytes]:
        key: bytes = problem["key"]
        if len(key) not in _AES_KEY_SIZES:
            # Let cryptography raise its own error for invalid key sizes; this is only a fast path.
            raise ValueError("Invalid AES key length")

        nonce: bytes = problem["nonce"]
        plaintext: bytes = problem["plaintext"]
        aad: Optional[bytes] = problem.get("associated_data", None)

        # Use lower-level Cipher API to avoid extra copy of ciphertext
        cipher = Cipher(algorithms.AES(key), modes.GCM(nonce))
        encryptor = cipher.encryptor()
        if aad:
            encryptor.authenticate_additional_data(aad)
        ciphertext = encryptor.update(plaintext) + encryptor.finalize()
        tag = encryptor.tag

        return {"ciphertext": ciphertext, "tag": tag}