from __future__ import annotations

import json
import time

import requests
from requests.exceptions import RequestException, Timeout

from core.config import settings


class HSRApiError(Exception):
    def __init__(self, message: str, *, retryable: bool = False):
        super().__init__(message)
        self.retryable = retryable


def _redact(text: str) -> str:
    return text.replace(settings.hsr_api_auth_key, "[REDACTED]") if settings.hsr_api_auth_key else text


def _request(url: str, params: dict) -> requests.Response:
    return requests.get(
        url,
        params=params,
        timeout=(settings.request_connect_timeout_sec, settings.request_read_timeout_sec),
    )


def call_hsr_file_list(base_datetime: str) -> tuple[str, list[str]]:
    if not settings.hsr_api_auth_key:
        raise HSRApiError("Missing HSR_API_AUTH_KEY")

    params = {
        "cmp": "HSR",
        "tm": base_datetime,
        "authKey": settings.hsr_api_auth_key,
    }
    attempts = settings.request_retry_count + 1

    for attempt in range(1, attempts + 1):
        try:
            response = _request(settings.hsr_file_list_url, params)
            response.raise_for_status()
            text = response.text.strip()

            if text.startswith("{"):
                data = json.loads(text)
                result = data.get("result", {})
                status = int(result.get("status", 0) or 0)
                message = result.get("message", "")
                if status != 200:
                    retryable = status >= 500 or status == 429
                    raise HSRApiError(
                        f"HSR API error: status={status}, message={message}",
                        retryable=retryable,
                    )

            lines = [line.strip() for line in text.splitlines() if line.strip()]
            return text, lines
        except Timeout as exc:
            error = HSRApiError(_redact(f"Timed out calling HSR API: {exc}"), retryable=True)
        except RequestException as exc:
            status_code = getattr(exc.response, "status_code", None)
            retryable = status_code is None or status_code >= 500 or status_code == 429
            error = HSRApiError(
                _redact(f"HTTP error calling HSR API: status={status_code}, detail={exc}"),
                retryable=retryable,
            )
        except ValueError as exc:
            error = HSRApiError(_redact(f"Failed to decode HSR API response: {exc}"))
        except HSRApiError as exc:
            error = exc

        if not error.retryable or attempt == attempts:
            raise error

        sleep_seconds = settings.request_retry_backoff_sec * (2 ** (attempt - 1))
        time.sleep(sleep_seconds)

    raise HSRApiError("Unknown HSR API error")


def call_hsr_area(
    base_datetime: str,
    dong_code: str,
    *,
    comp_type: str | None = None,
    data_type_cd: str | None = None,
) -> tuple[dict, list[dict], int]:
    if not settings.hsr_api_auth_key:
        raise HSRApiError("Missing HSR_API_AUTH_KEY")

    params = {
        "pageNo": 1,
        "numOfRows": 10,
        "dataType": "JSON",
        "dateTime": base_datetime,
        "compType": comp_type or settings.hsr_area_comp_type,
        "dataTypeCd": data_type_cd or settings.hsr_area_data_type_cd,
        "dongCode": dong_code,
        "authKey": settings.hsr_api_auth_key,
    }
    attempts = settings.request_retry_count + 1

    for attempt in range(1, attempts + 1):
        try:
            response = _request(settings.hsr_area_url, params)
            response.raise_for_status()
            payload = response.json()
            header = payload.get("response", {}).get("header", {})
            result_code = str(header.get("resultCode", ""))
            if result_code == "00":
                items = payload.get("response", {}).get("body", {}).get("items", {}).get("item", [])
                if isinstance(items, dict):
                    items = [items]
                return payload, items, response.status_code
            if result_code == "03":
                raise HSRApiError(
                    f"HSR area API returned no data: base_datetime={base_datetime}, dong_code={dong_code}"
                )

            raise HSRApiError(
                "HSR area API error: "
                f"resultCode={result_code}, resultMsg={header.get('resultMsg', '')}, "
                f"base_datetime={base_datetime}, dong_code={dong_code}"
            )
        except Timeout as exc:
            error = HSRApiError(_redact(f"Timed out calling HSR area API: {exc}"), retryable=True)
        except RequestException as exc:
            status_code = getattr(exc.response, "status_code", None)
            retryable = status_code is None or status_code >= 500 or status_code == 429
            error = HSRApiError(
                _redact(f"HTTP error calling HSR area API: status={status_code}, detail={exc}"),
                retryable=retryable,
            )
        except ValueError as exc:
            error = HSRApiError(_redact(f"Failed to decode HSR area API response: {exc}"))
        except HSRApiError as exc:
            error = exc

        if not error.retryable or attempt == attempts:
            raise error

        sleep_seconds = settings.request_retry_backoff_sec * (2 ** (attempt - 1))
        time.sleep(sleep_seconds)

    raise HSRApiError("Unknown HSR area API error")
