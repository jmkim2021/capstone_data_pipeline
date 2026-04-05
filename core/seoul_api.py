from __future__ import annotations

import time

import requests
from requests.exceptions import RequestException, Timeout

from core.config import settings


class SeoulApiError(Exception):
    def __init__(self, message: str, *, retryable: bool = False):
        super().__init__(message)
        self.retryable = retryable


def _redact(text: str, api_key: str) -> str:
    return text.replace(api_key, "[REDACTED]") if api_key else text


def _request(url: str) -> dict:
    try:
        response = requests.get(
            url,
            timeout=(settings.request_connect_timeout_sec, settings.request_read_timeout_sec),
        )
        response.raise_for_status()
        return response.json()
    except Timeout as exc:
        raise SeoulApiError(f"Timed out calling Seoul API: {exc}", retryable=True) from exc
    except RequestException as exc:
        status_code = getattr(exc.response, "status_code", None)
        retryable = status_code is None or status_code >= 500 or status_code == 429
        raise SeoulApiError(
            f"HTTP error calling Seoul API: status={status_code}, detail={exc}",
            retryable=retryable,
        ) from exc
    except ValueError as exc:
        raise SeoulApiError(f"Failed to decode Seoul API JSON: {exc}") from exc


def call_seoul_list_api_payload(
    service_name: str,
    api_key: str,
    start_index: int,
    end_index: int,
) -> dict:
    if not api_key:
        raise SeoulApiError(f"Missing API key for Seoul service: {service_name}")

    url = (
        f"{settings.seoul_api_base_url}/{api_key}/json/{service_name}/"
        f"{start_index}/{end_index}/"
    )
    attempts = settings.request_retry_count + 1

    for attempt in range(1, attempts + 1):
        try:
            data = _request(url)
            payload = data.get(service_name)
            if payload is None:
                result = data.get("RESULT", {})
                raise SeoulApiError(
                    f"Unexpected Seoul API response for {service_name}: {result or data}"
                )

            result = payload.get("RESULT", {})
            code = result.get("CODE")
            if code != "INFO-000":
                retryable = code in {"INFO-200", "ERROR-300", "ERROR-500"}
                raise SeoulApiError(
                    f"Seoul API error for {service_name}: code={code}, message={result.get('MESSAGE')}",
                    retryable=retryable,
                )

            rows = payload.get("row", [])
            if not isinstance(rows, list):
                raise SeoulApiError(f"Unexpected row type for {service_name}: {type(rows).__name__}")
            return payload
        except SeoulApiError as exc:
            if not exc.retryable or attempt == attempts:
                raise
            sleep_seconds = settings.request_retry_backoff_sec * (2 ** (attempt - 1))
            time.sleep(sleep_seconds)

    return {}


def call_seoul_list_api(service_name: str, api_key: str, start_index: int, end_index: int) -> list[dict]:
    payload = call_seoul_list_api_payload(service_name, api_key, start_index, end_index)
    rows = payload.get("row", [])
    return [row for row in rows if isinstance(row, dict)]
