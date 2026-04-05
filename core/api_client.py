from __future__ import annotations

import time

import requests
from requests import Response
from requests.exceptions import RequestException, Timeout

from core.config import settings


class KMAApiError(Exception):
    def __init__(self, message: str, *, retryable: bool = False):
        super().__init__(message)
        self.retryable = retryable


def _normalize_items(items: object) -> list[dict]:
    if items is None:
        return []
    if isinstance(items, list):
        return [item for item in items if isinstance(item, dict)]
    if isinstance(items, dict):
        return [items]
    raise KMAApiError(f"Unexpected item type: {type(items).__name__}")


def _parse_response(data: dict) -> tuple[list[dict], int]:
    try:
        response = data["response"]
        header = response["header"]
        result_code = header["resultCode"]
        result_msg = header.get("resultMsg", "")
    except KeyError as exc:
        raise KMAApiError(f"Unexpected response format: {data}") from exc

    if result_code != "00":
        retryable = result_code in {"03", "04"}
        raise KMAApiError(
            f"KMA API error: resultCode={result_code}, resultMsg={result_msg}",
            retryable=retryable,
        )

    body = response.get("body", {})
    total_count = int(body.get("totalCount", 0) or 0)
    items = body.get("items", {}).get("item")
    return _normalize_items(items), total_count


def _request_page(url: str, params: dict) -> Response:
    try:
        response = requests.get(
            url,
            params=params,
            timeout=(settings.request_connect_timeout_sec, settings.request_read_timeout_sec),
        )
        response.raise_for_status()
        return response
    except Timeout as exc:
        raise KMAApiError(f"Timed out calling KMA API: {exc}", retryable=True) from exc
    except RequestException as exc:
        status_code = getattr(exc.response, "status_code", None)
        retryable = status_code is None or status_code >= 500 or status_code == 429
        raise KMAApiError(
            f"HTTP error calling KMA API: status={status_code}, detail={exc}",
            retryable=retryable,
        ) from exc


def _validate_base_time(items: list[dict], expected_base_date: str, expected_base_time: str) -> bool:
    for item in items:
        item_base_date = item.get("baseDate")
        item_base_time = item.get("baseTime")
        if item_base_date is None or item_base_time is None:
            continue
        if item_base_date != expected_base_date or item_base_time != expected_base_time:
            return False
    return True


def call_kma(endpoint: str, base_date: str, base_time: str, nx: int, ny: int) -> list[dict]:
    url = f"{settings.kma_base_url}/{endpoint}"
    base_params = {
        "serviceKey": settings.kma_service_key,
        "numOfRows": settings.page_size,
        "dataType": "JSON",
        "base_date": base_date,
        "base_time": base_time,
        "nx": nx,
        "ny": ny,
    }

    attempts = settings.request_retry_count + 1
    last_error: KMAApiError | None = None

    for attempt in range(1, attempts + 1):
        try:
            page_no = 1
            total_count: int | None = None
            all_items: list[dict] = []

            while total_count is None or len(all_items) < total_count:
                params = dict(base_params)
                params["pageNo"] = page_no
                response = _request_page(url, params)
                data = response.json()
                items, total_count = _parse_response(data)
                all_items.extend(items)

                if not items or len(items) < settings.page_size:
                    break
                page_no += 1

            _validate_base_time(all_items, base_date, base_time)
            return all_items
        except KMAApiError as exc:
            last_error = exc
            if not exc.retryable or attempt == attempts:
                raise
            sleep_seconds = settings.request_retry_backoff_sec * (2 ** (attempt - 1))
            time.sleep(sleep_seconds)
        except ValueError as exc:
            raise KMAApiError(f"Failed to decode KMA API response JSON: {exc}") from exc

    if last_error is not None:
        raise last_error
    raise KMAApiError("Unknown KMA API error")