from typing import Any, Dict, Optional

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

# Allowed AES key lengths (bytes)
_AES_KEY_SIZES = {16, 24, 32}


class Solver:
    """
    High-speed AES-GCM encryption.

    Input dict keys:
      • key             : bytes (16/24/32 bytes)
      • nonce           : bytes (12 bytes recommended)
      • plaintext       : bytes
      • associated_data : bytes | None

    Output dict keys:
      • ciphertext : bytes
      • tag        : bytes
    """

    __slots__ = ()  # no per-instance attribute dict

    def solve(self, problem: Dict[str, Any], **kwargs) -> Dict[str, bytes]:
        # Fast local look-ups
        key: bytes = problem["key"]
        if len(key) not in _AES_KEY_SIZES:
            raise ValueError("Invalid AES key length")

        nonce: bytes = problem["nonce"]
        plaintext: bytes = problem["plaintext"]
        aad: Optional[bytes] = problem.get("associated_data") or None

        # Initialise encryptor (OpenSSL-backed, very fast)
        encryptor = Cipher(algorithms.AES(key), modes.GCM(nonce)).encryptor()

        if aad:
            encryptor.authenticate_additional_data(aad)

        # Encrypt – update() returns ciphertext directly, no extra Python copies
        ciphertext = encryptor.update(plaintext)
        tail = encryptor.finalize()  # usually empty for GCM, but handle generically
        if tail:
            ciphertext += tail

        tag = encryptor.tag  # 16-byte authentication tag

        return {"ciphertext": ciphertext, "tag": tag}