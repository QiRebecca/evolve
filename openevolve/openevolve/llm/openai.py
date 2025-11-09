"""
OpenAI API interface for LLMs
"""

import asyncio
import logging
import time
from typing import Any, Dict, List, Optional, Union

import openai

from openevolve.config import LLMConfig
from openevolve.llm.base import LLMInterface

logger = logging.getLogger(__name__)


class OpenAILLM(LLMInterface):
    """LLM interface using OpenAI-compatible APIs"""

    def __init__(
        self,
        model_cfg: Optional[dict] = None,
    ):
        self.model = model_cfg.name
        self.system_message = model_cfg.system_message
        self.temperature = model_cfg.temperature
        self.top_p = model_cfg.top_p
        self.max_tokens = model_cfg.max_tokens
        self.timeout = model_cfg.timeout
        self.retries = model_cfg.retries
        self.retry_delay = model_cfg.retry_delay
        self.api_base = model_cfg.api_base
        self.api_key = model_cfg.api_key
        self.random_seed = getattr(model_cfg, "random_seed", None)
        self.reasoning_effort = getattr(model_cfg, "reasoning_effort", None)
        self.verbosity = getattr(model_cfg, "verbosity", None)
        
        # Thread-local storage for reasoning content from o3/o1 models
        import threading
        self._thread_local = threading.local()

        # Set up API client
        # OpenAI client requires max_retries to be int, not None
        max_retries = self.retries if self.retries is not None else 0
        self.client = openai.OpenAI(
            api_key=self.api_key,
            base_url=self.api_base,
            timeout=self.timeout,
            max_retries=max_retries,
        )

        # Only log unique models to reduce duplication
        if not hasattr(logger, "_initialized_models"):
            logger._initialized_models = set()

        if self.model not in logger._initialized_models:
            logger.info(f"Initialized OpenAI LLM with model: {self.model}")
            logger._initialized_models.add(self.model)
    
    def get_last_reasoning(self) -> Optional[str]:
        """Get the reasoning from the last API call (for o3/o1 models)"""
        return getattr(self._thread_local, 'last_reasoning', None)
    
    def get_last_full_response(self) -> Optional[Any]:
        """Get the full response object from the last API call"""
        return getattr(self._thread_local, 'last_full_response', None)

    async def generate(self, prompt: str, **kwargs) -> str:
        """Generate text from a prompt"""
        return await self.generate_with_context(
            system_message=self.system_message,
            messages=[{"role": "user", "content": prompt}],
            **kwargs,
        )

    async def generate_with_context(
        self, system_message: str, messages: List[Dict[str, str]], **kwargs
    ) -> str:
        """Generate text using a system message and conversational context"""
        # Prepare messages with system message
        formatted_messages = [{"role": "system", "content": system_message}]
        formatted_messages.extend(messages)

        # Set up generation parameters
        # Define OpenAI reasoning models that require max_completion_tokens
        # These models don't support temperature/top_p and use different parameters
        OPENAI_REASONING_MODEL_PREFIXES = (
            # O-series reasoning models
            "o1-",
            "o1",  # o1, o1-mini, o1-preview
            "o3-",
            "o3",  # o3, o3-mini, o3-pro
            "o4-",  # o4-mini
            # GPT-5 series are also reasoning models
            "gpt-5-",
            "gpt-5",  # gpt-5, gpt-5-mini, gpt-5-nano
            # The GPT OSS series are also reasoning models
            "gpt-oss-120b",
            "gpt-oss-20b",
        )

        # Check if this is a reasoning model (o3, o1, etc.)
        # Reasoning models don't support temperature/top_p regardless of API provider
        model_lower = str(self.model).lower()
        is_reasoning_model = model_lower.startswith(OPENAI_REASONING_MODEL_PREFIXES)
        
        # Check if using official OpenAI API (for reasoning-specific parameters)
        is_official_openai_api = (self.api_base == "https://api.openai.com/v1" or self.api_base is None)

        if is_reasoning_model:
            # For reasoning models: don't use temperature/top_p (not supported)
            # Use max_completion_tokens for official API, max_tokens for third-party APIs
            params = {
                "model": self.model,
                "messages": formatted_messages,
            }
            
            if is_official_openai_api:
                # Official OpenAI API supports reasoning model parameters
                params["max_completion_tokens"] = kwargs.get("max_tokens", self.max_tokens)
                # Add optional reasoning parameters if provided
                reasoning_effort = kwargs.get("reasoning_effort", self.reasoning_effort)
                if reasoning_effort is not None:
                    params["reasoning_effort"] = reasoning_effort
                verbosity = kwargs.get("verbosity", self.verbosity)
                if verbosity is not None:
                    params["verbosity"] = verbosity
            else:
                # Third-party APIs: use max_tokens instead of max_completion_tokens
                # Don't include reasoning_effort/verbosity as they may not be supported
                params["max_tokens"] = kwargs.get("max_tokens", self.max_tokens)
        else:
            # Standard parameters for all other models
            params = {
                "model": self.model,
                "messages": formatted_messages,
                "temperature": kwargs.get("temperature", self.temperature),
                "top_p": kwargs.get("top_p", self.top_p),
                "max_tokens": kwargs.get("max_tokens", self.max_tokens),
            }

            # Handle reasoning_effort for open source reasoning models.
            reasoning_effort = kwargs.get("reasoning_effort", self.reasoning_effort)
            if reasoning_effort is not None:
                params["reasoning_effort"] = reasoning_effort

        # Add seed parameter for reproducibility if configured
        # Skip seed parameter for Google AI Studio endpoint as it doesn't support it
        seed = kwargs.get("seed", self.random_seed)
        if seed is not None:
            if self.api_base == "https://generativelanguage.googleapis.com/v1beta/openai/":
                logger.warning(
                    "Skipping seed parameter as Google AI Studio endpoint doesn't support it. "
                    "Reproducibility may be limited."
                )
            else:
                params["seed"] = seed

        # Attempt the API call with retries
        retries = kwargs.get("retries", self.retries)
        retry_delay = kwargs.get("retry_delay", self.retry_delay)
        timeout = kwargs.get("timeout", self.timeout)

        for attempt in range(retries + 1):
            try:
                response = await asyncio.wait_for(self._call_api(params), timeout=timeout)
                return response
            except asyncio.TimeoutError:
                if attempt < retries:
                    logger.warning(f"Timeout on attempt {attempt + 1}/{retries + 1}. Retrying...")
                    await asyncio.sleep(retry_delay)
                else:
                    logger.error(f"All {retries + 1} attempts failed with timeout")
                    raise
            except Exception as e:
                if attempt < retries:
                    logger.warning(
                        f"Error on attempt {attempt + 1}/{retries + 1}: {str(e)}. Retrying..."
                    )
                    await asyncio.sleep(retry_delay)
                else:
                    logger.error(f"All {retries + 1} attempts failed with error: {str(e)}")
                    raise

    async def _call_api(self, params: Dict[str, Any]) -> str:
        """Make the actual API call"""
        # Use asyncio to run the blocking API call in a thread pool
        loop = asyncio.get_event_loop()
        response = await loop.run_in_executor(
            None, lambda: self.client.chat.completions.create(**params)
        )
        
        # Logging of system prompt, user message and response content
        logger = logging.getLogger(__name__)
        logger.info(f"API parameters: {params}")
        
        # Extract the main content
        content = response.choices[0].message.content
        
        # Log detailed response info for debugging empty responses
        if content is None or (isinstance(content, str) and len(content.strip()) == 0):
            logger.warning(f"Empty or None content detected!")
            logger.warning(f"Response object type: {type(response)}")
            logger.warning(f"Response choices length: {len(response.choices) if response.choices else 0}")
            if response.choices:
                logger.warning(f"Response choices[0] type: {type(response.choices[0])}")
                logger.warning(f"Response choices[0].message type: {type(response.choices[0].message)}")
                logger.warning(f"Content value: {repr(content)}")
                # Try to get full response dump
                try:
                    if hasattr(response, 'model_dump'):
                        full_response = response.model_dump()
                        logger.warning(f"Full response dump (first 2000 chars): {str(full_response)[:2000]}")
                    else:
                        logger.warning(f"Full response str (first 2000 chars): {str(response)[:2000]}")
                except Exception as e:
                    logger.warning(f"Could not dump full response: {e}")
        
        logger.info(f"API response content length: {len(content) if content else 0}")
        
        # For reasoning models (o3, o1, etc.), also log reasoning if available
        if hasattr(response.choices[0].message, 'reasoning_content'):
            reasoning = response.choices[0].message.reasoning_content
            if reasoning:
                logger.info(f"O3 Reasoning Process (length={len(reasoning)}): {reasoning[:500]}...")
                # Store reasoning in a thread-local for later retrieval
                import threading
                if not hasattr(self, '_thread_local'):
                    self._thread_local = threading.local()
                self._thread_local.last_reasoning = reasoning
                self._thread_local.last_full_response = response.model_dump() if hasattr(response, 'model_dump') else str(response)
        else:
            logger.info("No reasoning_content attribute in response (第三方API可能不支持)")
        
        return content if content else ""
