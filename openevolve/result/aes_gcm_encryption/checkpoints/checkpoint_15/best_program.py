from typing import Any
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes


class Solver:
    TAG_SIZE = 16  # bytes (128-bit GCM tag)

    def solve(self, problem: dict[str, Any], **kwargs) -> dict[str, bytes]:
        """
        Encrypt plaintext with AES-GCM, returning ciphertext and tag.

        Parameters
        ----------
        problem : dict
            {
                "key": bytes,
                "nonce": bytes,
                "plaintext": bytes,
                "associated_data": bytes | None
            }

        Returns
        -------
        dict
            {
                "ciphertext": bytes,
                "tag": bytes   # 16-byte authentication tag
            }
        """
        key: bytes = problem["key"]
        nonce: bytes = problem["nonce"]
        plaintext: bytes = problem["plaintext"]
        aad: bytes | None = problem.get("associated_data", None)

        # Build low-level AES-GCM cipher (OpenSSL backend is chosen automatically)
        encryptor = Cipher(
            algorithms.AES(key),
            modes.GCM(nonce),
        ).encryptor()

        # Attach AAD if provided and non-empty
        if aad:
            encryptor.authenticate_additional_data(aad)

        # Single update is fastest; OpenSSL handles chunking internally
        ciphertext = encryptor.update(plaintext) + encryptor.finalize()
        tag = encryptor.tag  # 16-byte tag produced without extra copy

        return {"ciphertext": ciphertext, "tag": tag}