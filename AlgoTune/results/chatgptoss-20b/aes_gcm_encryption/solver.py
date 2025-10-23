from typing import Any
import hmac
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

# Constants matching the baseline implementation
AES_KEY_SIZES = (16, 24, 32)  # AES-128, AES-192, AES-256
GCM_TAG_SIZE = 16  # 128-bit authentication tag

class Solver:
    def solve(self, problem, **kwargs) -> Any:
        """
        Encrypt the plaintext using AES-GCM from the `cryptography` library.

        Args:
            problem (dict): The problem dictionary containing 'key', 'nonce',
                            'plaintext', and optionally 'associated_data'.

        Returns:
            dict: A dictionary containing 'ciphertext' and 'tag'.
        """
        key = problem["key"]
        nonce = problem["nonce"]
        plaintext = problem["plaintext"]
        associated_data = problem.get("associated_data")

        # Perform encryption
        aesgcm = AESGCM(key)
        ciphertext_with_tag = aesgcm.encrypt(nonce, plaintext, associated_data)

        # Split ciphertext and tag
        tag = ciphertext_with_tag[-GCM_TAG_SIZE:]
        ciphertext = ciphertext_with_tag[:-GCM_TAG_SIZE]

        return {"ciphertext": ciphertext, "tag": tag}