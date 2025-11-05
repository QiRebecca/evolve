from typing import Any, Dict
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

# ---------------------------------------------------------------------------
# Fast-path constants and cache (module-local for quickest lookup)
# ---------------------------------------------------------------------------
_VALID_KEY_SIZES = {16, 24, 32}   # Allowed AES key lengths (bytes)
_TAG_LEN = 16                     # Size of GCM authentication tag (bytes)

# Re-use AESGCM objects for identical keys to skip re-initialisation overhead.
# Capped to a modest size to avoid unbounded memory growth.
_AESGCM_CACHE: Dict[bytes, AESGCM] = {}


class Solver:
    """
    High-performance AES-GCM encryptor.

    Expected input dictionary keys:
        • key : bytes            (16/24/32 bytes)
        • nonce : bytes          (unique per encryption)
        • plaintext : bytes      (data to encrypt)
        • associated_data : bytes | None (optional AAD)

    Returns a dict with:
        • ciphertext : bytes – encrypted data (tag removed)
        • tag        : bytes – 16-byte authentication tag
    """

    __slots__ = ()  # prevent per-instance attribute dict

    def solve(self, problem: Dict[str, Any], **__) -> Dict[str, bytes]:
        # Local alias for minimum attribute/dict look-ups
        p = problem

        key: bytes = p["key"]
        # Quick key length validation (cryptography will also check, but earlier
        # failure avoids cipher cache pollution).
        if len(key) not in _VALID_KEY_SIZES:
            raise ValueError("AES key must be 16, 24, or 32 bytes long.")

        # Obtain (or create) a cached AESGCM instance for this key
        aes = _AESGCM_CACHE.get(key)
        if aes is None:
            aes = AESGCM(key)
            # Simple capped cache to keep memory usage negligible
            if len(_AESGCM_CACHE) < 128:
                _AESGCM_CACHE[key] = aes

        # Fast field extraction
        nonce: bytes = p["nonce"]
        plaintext: bytes = p["plaintext"]
        aad = p.get("associated_data") or None  # treat empty b'' as None

        # Perform encryption (cryptography appends 16-byte tag to ciphertext)
        ct_tag: bytes = aes.encrypt(nonce, plaintext, aad)

        # Split ciphertext and tag
        return {
            "ciphertext": ct_tag[:-_TAG_LEN],
            "tag": ct_tag[-_TAG_LEN:],
        }
