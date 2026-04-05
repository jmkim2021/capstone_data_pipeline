from __future__ import annotations

import argparse
from datetime import date, datetime, timedelta
import time
import json
from pathlib import Path
import sys
import os

import requests
from psycopg2.extras import Json, execute_values

from core.config import settings
from core.db import get_conn
from core.kma_time import now_kst

SERVICE_NAME = "SPOP_LOCAL_RESD_JACHI"

# OA-15439 응답의 ADSTRD_CODE_SE(5자리) -> 프로젝트 표준 district_name 매핑
DISTRICT_CODE_TO_NAME: dict[str, str] = {
    "11110": "종로구",
    "11140": "중구",
    "11170": "용산구",
    "11200": "성동구",
    "11215": "광진구",
    "11230": "동대문구",
    "11260": "중랑구",
    "11290": "성북구",
    "11305": "강북구",
    "11320": "도봉구",
    "11350": "노원구",
    "11380": "은평구",
    "11410": "서대문구",
    "11440": "마포구",
    "11470": "양천구",
    "11500": "강서구",
    "11530": "구로구",
    "11545": "금천구",
    "11560": "영등포구",
    "11590": "동작구",
    "11620": "관악구",
    "11650": "서초구",
    "11680": "강남구",
    "11710": "송파구",
    "11740": "강동구",
}

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.append(str(PROJECT_ROOT))


class SeoulApiError(Exception):
    def __init__(self, message: str, *, retryable: bool = False):
        super().__init__(message)
        self.retryable = retryable


def _request_json(url: str, *, api_key: str) -> dict:
    try:
        resp = requests.get(
            url,
            timeout=(settings.request_connect_timeout_sec, settings.request_read_timeout_sec),
        )
        resp.raise_for_status()
        return resp.json()
    except requests.exceptions.Timeout as exc:
        raise SeoulApiError(f"Timed out calling Seoul OpenAPI: {exc}", retryable=True) from exc
    except requests.exceptions.RequestException as exc:
        status_code = getattr(exc.response, "status_code", None)
        retryable = status_code is None or status_code >= 500 or status_code == 429
        raise SeoulApiError(
            f"HTTP error calling Seoul OpenAPI: status={status_code}, detail={exc}",
            retryable=retryable,
        ) from exc
    except ValueError as exc:
        raise SeoulApiError(f"Failed to decode Seoul OpenAPI JSON: {exc}") from exc


def call_seoul_living_population_payload(
    *,
    api_key: str,
    start_index: int,
    end_index: int,
    base_date_str: str,
    base_hour_str: str,
) -> dict:
    """
    OA-15439 Sheet/OpenAPI:
    - json/{SERVICE_NAME}/{start}/{end}/{STDR_DE_ID}/{TMZON_PD_SE}/
    """
    url = (
        f"{settings.seoul_api_base_url}/{api_key}/json/{SERVICE_NAME}/"
        f"{start_index}/{end_index}/{base_date_str}/{base_hour_str}/"
    )

    attempts = settings.request_retry_count + 1
    last_exc: Exception | None = None

    for attempt in range(1, attempts + 1):
        try:
            data = _request_json(url, api_key=api_key)
            payload = data.get(SERVICE_NAME)
            if payload is None:
                # Some payloads may use different casing (rare, but keep defensive)
                payload = data.get(SERVICE_NAME.lower())
            if payload is None:
                raise SeoulApiError(f"Unexpected payload container for {SERVICE_NAME}: {list(data.keys())}")

            result = payload.get("RESULT", {})
            code = result.get("CODE")
            if code != "INFO-000":
                retryable = code in {"INFO-200", "ERROR-300", "ERROR-500"}
                raise SeoulApiError(
                    f"Seoul API error: code={code}, message={result.get('MESSAGE')}",
                    retryable=retryable,
                )

            rows = payload.get("row", [])
            if not isinstance(rows, list):
                raise SeoulApiError(f"Unexpected row type: {type(rows).__name__}")

            return payload
        except SeoulApiError as exc:
            last_exc = exc
            if not exc.retryable or attempt == attempts:
                raise
            time.sleep(settings.request_retry_backoff_sec * (2 ** (attempt - 1)))

    assert last_exc is not None
    raise last_exc


def parse_date(value: str) -> date:
    value = value.strip()
    if "-" in value:
        return datetime.strptime(value, "%Y-%m-%d").date()
    return datetime.strptime(value, "%Y%m%d").date()


def daterange(start: date, end: date):
    current = start
    while current <= end:
        yield current
        current += timedelta(days=1)


def build_upsert_rows(
    *,
    api_rows: list[dict],
    requested_date: date,
    ingested_at: datetime,
) -> list[tuple]:
    out: list[tuple] = []
    for row in api_rows:
        st = row.get("STDR_DE_ID")
        tm = row.get("TMZON_PD_SE")
        dc = row.get("ADSTRD_CODE_SE")
        tot = row.get("TOT_LVPOP_CO")

        if not (st and tm and dc and tot not in (None, "")):
            # 필수키 누락 → 해당 행만 스킵
            continue

        base_dt = datetime.strptime(str(st), "%Y%m%d").date()
        base_hour = int(str(tm))
        district_code = str(dc)

        district_name = DISTRICT_CODE_TO_NAME.get(district_code)
        if district_name is None:
            raise ValueError(f"Missing district_name mapping for district_code={district_code}")

        korean_population = float(tot)

        # source_date: OA 응답에 별도 '공개일' 필드가 없어 STDR_DE_ID(집계 기준 캘린더 일)와 동일.
        # base_date/base_hour가 실제 데이터 시점; requested_date는 수집 잡이 요청한 날짜.
        out.append(
            (
                base_dt,
                base_hour,
                district_code,
                district_name,
                korean_population,
                base_dt,
                SERVICE_NAME,
                requested_date,
                ingested_at,
                ingested_at,
                Json(row),
            )
        )

    return out


UPSERT_SQL = """
INSERT INTO ref.seoul_living_population_korean_district_hourly (
    base_date, base_hour,
    district_code, district_name,
    korean_population,
    source_date, source_name,
    requested_date,
    ingested_at, updated_at,
    row_json
) VALUES %s
ON CONFLICT (base_date, base_hour, district_code)
DO UPDATE SET
    district_name = EXCLUDED.district_name,
    korean_population = EXCLUDED.korean_population,
    source_date = EXCLUDED.source_date,
    source_name = EXCLUDED.source_name,
    requested_date = EXCLUDED.requested_date,
    ingested_at = EXCLUDED.ingested_at,
    updated_at = EXCLUDED.updated_at,
    row_json = EXCLUDED.row_json
"""


def upsert_hourly_rows(rows: list[tuple]) -> int:
    if not rows:
        return 0
    with get_conn() as conn:
        with conn.cursor() as cur:
            execute_values(cur, UPSERT_SQL, rows, page_size=500)
        conn.commit()
    return len(rows)


def fetch_hourly_rows(
    *,
    api_key: str,
    base_date: date,
    base_hour: int,
    page_size: int,
) -> tuple[int, list[dict]]:
    base_date_str = base_date.strftime("%Y%m%d")
    base_hour_str = f"{base_hour:02d}"

    start_index = 1
    all_rows: list[dict] = []
    total_count: int | None = None

    while True:
        end_index = start_index + page_size - 1
        payload = call_seoul_living_population_payload(
            api_key=api_key,
            start_index=start_index,
            end_index=end_index,
            base_date_str=base_date_str,
            base_hour_str=base_hour_str,
        )

        if total_count is None:
            total_count = int(payload.get("list_total_count") or 0)

        page_rows = payload.get("row", [])
        all_rows.extend(page_rows)

        if total_count == 0:
            break
        if len(all_rows) >= total_count:
            break
        if not page_rows:
            break

        start_index += page_size

        # 방어: max 1000건 제한에 맞춰 호출 종료
        if start_index > 1000:
            break

    return total_count or 0, all_rows


def probe_date_has_data(
    *,
    api_key: str,
    candidate_date: date,
    probe_hour: int,
) -> bool:
    base_date_str = candidate_date.strftime("%Y%m%d")
    base_hour_str = f"{probe_hour:02d}"
    payload = call_seoul_living_population_payload(
        api_key=api_key,
        start_index=1,
        end_index=1,
        base_date_str=base_date_str,
        base_hour_str=base_hour_str,
    )
    total_count = int(payload.get("list_total_count") or 0)
    rows = payload.get("row", [])
    return total_count > 0 and bool(rows)


def date_has_open_data(
    *,
    api_key: str,
    candidate_date: date,
    probe_hours: tuple[int, ...] = (12, 0, 23, 6, 18),
) -> bool:
    """
    OA-15439는 일자 단위로 공개되며, 특정 시각만 비는 경우가 있어
    여러 시각을 순서대로 시도한다(과거 0·23 동시 필수 요구는 운영에서 과도하게 보수적).
    """
    for h in probe_hours:
        try:
            if probe_date_has_data(api_key=api_key, candidate_date=candidate_date, probe_hour=h):
                return True
        except Exception:
            continue
    return False


def find_latest_available_source_date(
    *,
    api_key: str,
    requested_date: date,
    lookback_days: int,
) -> date:
    last_err: Exception | None = None
    for offset in range(0, lookback_days + 1):
        candidate = requested_date - timedelta(days=offset)
        try:
            if date_has_open_data(api_key=api_key, candidate_date=candidate):
                return candidate
        except Exception as exc:
            last_err = exc
            continue
    raise RuntimeError(
        f"Could not find latest STDR calendar day within lookback_days={lookback_days} "
        f"(requested_date={requested_date}). last_err={last_err}"
    )


def ingest_date(
    *,
    api_key: str,
    requested_date: date,
    source_date: date,
    hour_start: int,
    hour_end: int,
    page_size: int,
    dry_run: bool,
) -> dict[str, int]:
    ingested_at = now_kst()
    total_upserted = 0
    total_skipped_hours = 0

    for hour in range(hour_start, hour_end + 1):
        try:
            list_total, api_rows = fetch_hourly_rows(
                api_key=api_key,
                base_date=source_date,
                base_hour=hour,
                page_size=page_size,
            )
        except Exception as exc:
            print(
                f"[seoul_living_population_korean_district_hourly] "
                f"api_failed load_stdr_date={source_date} hour={hour}: {exc}"
            )
            continue

        if not api_rows or list_total == 0:
            total_skipped_hours += 1
            print(
                f"[seoul_living_population_korean_district_hourly] "
                f"no_data load_stdr_date={source_date} hour={hour} requested_date={requested_date}"
            )
            continue

        # upsert를 위한 ref row build
        rows = build_upsert_rows(
            api_rows=api_rows,
            requested_date=requested_date,
            ingested_at=ingested_at,
        )
        upserted = 0 if dry_run else upsert_hourly_rows(rows)
        total_upserted += upserted

        print(
            f"[seoul_living_population_korean_district_hourly] "
            f"loaded load_stdr_date={source_date} hour={hour} requested_date={requested_date} "
            f"api_list_total={list_total} rows_received={len(api_rows)} rows_upserted={len(rows) if dry_run else upserted}"
        )

    return {"upserted_rows": total_upserted, "skipped_hours": total_skipped_hours}


def main() -> None:
    parser = argparse.ArgumentParser(description="Load OA-15439 living population (Korean residents) by district/hour.")
    parser.add_argument("--mode", choices=["daily", "backfill"], required=True)
    parser.add_argument(
        "--target-date",
        type=str,
        help="daily mode: requested date (YYYY-MM-DD or YYYYMMDD); 생략 시 KST 당일",
    )
    parser.add_argument("--start-date", type=str, help="backfill mode: start date (YYYY-MM-DD or YYYYMMDD)")
    parser.add_argument("--end-date", type=str, help="backfill mode: end date (YYYY-MM-DD or YYYYMMDD)")
    parser.add_argument("--lookback-days", type=int, default=7, help="daily: lookback window for finding latest source_date")
    parser.add_argument("--resolve-missing-by-lookback", action="store_true", help="backfill: missing date를 lookback으로 대체")
    parser.add_argument("--hour-start", type=int, default=0)
    parser.add_argument("--hour-end", type=int, default=23)
    parser.add_argument("--page-size", type=int, default=min(1000, settings.seoul_api_page_size))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    api_key = os.getenv("SEOUL_OPEN_API_KEY", "").strip()

    if not api_key:
        raise RuntimeError("Missing env SEOUL_OPEN_API_KEY")

    hour_start = max(0, args.hour_start)
    hour_end = min(23, args.hour_end)
    if hour_start > hour_end:
        raise ValueError("hour-start must be <= hour-end")

    if args.mode == "daily":
        if args.target_date:
            requested = parse_date(args.target_date)
        else:
            requested = now_kst().date()
        source = find_latest_available_source_date(
            api_key=api_key,
            requested_date=requested,
            lookback_days=args.lookback_days,
        )
        print(
            f"[seoul_living_population_korean_district_hourly] daily requested_date={requested} "
            f"resolved_stdr_calendar_date={source} (API slice / STDR_DE_ID for load)"
        )
        ingest_date(
            api_key=api_key,
            requested_date=requested,
            source_date=source,
            hour_start=hour_start,
            hour_end=hour_end,
            page_size=min(1000, args.page_size),
            dry_run=args.dry_run,
        )
        return

    # backfill
    if not args.start_date or not args.end_date:
        raise ValueError("--start-date and --end-date are required for backfill mode")

    start = parse_date(args.start_date)
    end = parse_date(args.end_date)
    if start > end:
        raise ValueError("--start-date must be <= --end-date")

    for requested in daterange(start, end):
        try:
            if args.resolve_missing_by_lookback:
                source = find_latest_available_source_date(
                    api_key=api_key,
                    requested_date=requested,
                    lookback_days=args.lookback_days,
                )
            else:
                source = requested

            result = ingest_date(
                api_key=api_key,
                requested_date=requested,
                source_date=source,
                hour_start=hour_start,
                hour_end=hour_end,
                page_size=min(1000, args.page_size),
                dry_run=args.dry_run,
            )
            print(
                f"[seoul_living_population_korean_district_hourly] backfill done requested_date={requested} "
                f"load_stdr_date={source} result={json.dumps(result, ensure_ascii=False)}"
            )
        except Exception as exc:
            print(
                f"[seoul_living_population_korean_district_hourly] backfill failed requested_date={requested}: {exc}"
            )
            continue


if __name__ == "__main__":
    main()

