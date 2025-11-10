from typing import Any, Dict

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend


class Solver:
    """
    Fast AES-GCM encryption task solver.

    The method `solve` receives a problem dictionary with keys:
        - key: bytes (16/24/32 bytes)
        - nonce: bytes (recommended 12 bytes, but any length accepted by GCM)
        - plaintext: bytes
        - associated_data: bytes | None
    It returns a dict with:
        - 'ciphertext': encrypted bytes (no authentication tag)
        - 'tag'       : 16-byte GCM authentication tag
    The implementation uses the low-level Cipher/GCM API so the ciphertext and
    tag are produced separately, avoiding the extra copy inherent in
    AESGCM.encrypt(), thus improving performance for large payloads.
    """

    # Valid AES key lengths (bytes)
    _VALID_KEY_SIZES = {16, 24, 32}
    _TAG_SIZE = 16  # bytes

    # Small cache of AES algorithm objects keyed by the raw key to avoid
    # rebuilding the key schedule on repeated invocations with the same key.
    _alg_cache: Dict[bytes, algorithms.AES] = {}

    @classmethod
    def _get_aes_algo(cls, key: bytes) -> algorithms.AES:
        """
        Return (and cache) an algorithms.AES instance for the provided key.
        """
        algo = cls._alg_cache.get(key)
        if algo is None:
            algo = algorithms.AES(key)
            # Keep cache size bounded to avoid unbounded growth.
            if len(cls._alg_cache) < 128:  # arbitrary small cache size
                cls._alg_cache[key] = algo
        return algo

    def solve(self, problem: dict, **kwargs) -> dict:
        key: bytes = problem["key"]
        nonce: bytes = problem["nonce"]
        plaintext: bytes = problem["plaintext"]
        aad: bytes | None = problem.get("associated_data", None)

        # Minimal key length validation (cheap and avoids underlying library error)
        if len(key) not in self._VALID_KEY_SIZES:
            raise ValueError("Invalid AES key length; must be 16, 24 or 32 bytes")

        # Obtain (possibly cached) AES algorithm object
        algorithm = self._get_aes_algo(key)

        # Build Cipher each call (cheap) – backend optional in recent versions
        cipher = Cipher(algorithm, modes.GCM(nonce), backend=default_backend())
        encryptor = cipher.encryptor()

        if aad:
            # Authenticate additional data only if provided and non-empty
            encryptor.authenticate_additional_data(aad)

        # Encrypt in a single call; update() returns ciphertext bytes
        ciphertext = encryptor.update(plaintext) + encryptor.finalize()
        tag = encryptor.tag  # 16-byte authentication tag

        # Return result exactly as expected (ciphertext without tag)
        return {"ciphertext": ciphertext, "tag": tag}