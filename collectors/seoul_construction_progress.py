from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path
import sys

from psycopg2.extras import Json, execute_values

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.append(str(PROJECT_ROOT))

from core.db import get_conn
from core.kma_time import now_kst
from core.seoul_api import SeoulApiError, call_seoul_list_api_payload


SERVICE_NAME = "ListOnePMISBizInfo"
DEFAULT_API_KEY = "6d53784c66776f61353165706d7465"
SEOUL_DISTRICT_NAMES = [
    "종로구",
    "중구",
    "용산구",
    "성동구",
    "광진구",
    "동대문구",
    "중랑구",
    "성북구",
    "강북구",
    "도봉구",
    "노원구",
    "은평구",
    "서대문구",
    "마포구",
    "양천구",
    "강서구",
    "구로구",
    "금천구",
    "영등포구",
    "동작구",
    "관악구",
    "서초구",
    "강남구",
    "송파구",
    "강동구",
]


def _clean_text(value: object | None) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _normalize_district_name(*candidates: object | None) -> str | None:
    for candidate in candidates:
        text = _clean_text(candidate)
        if text is None:
            continue
        for district_name in SEOUL_DISTRICT_NAMES:
            if text == district_name or district_name in text:
                return district_name
    return None


def _normalize_completion_status(status_text: object | None, status_flag: object | None) -> str | None:
    text = _clean_text(status_text)
    if text:
        compact = text.replace(" ", "")
        if "준공" in compact:
            return "준공"
        if "진행" in compact:
            return "진행"
        return text

    flag = _clean_text(status_flag)
    if flag == "0":
        return "준공"
    if flag == "1":
        return "진행"
    return None


def _make_row_hash(row: dict[str, object]) -> str:
    payload = json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _fetch_all_rows(api_key: str, page_size: int) -> list[dict]:
    payload = call_seoul_list_api_payload(
        service_name=SERVICE_NAME,
        api_key=api_key,
        start_index=1,
        end_index=page_size,
    )
    total_count = int(payload.get("list_total_count") or 0)
    rows = [row for row in payload.get("row", []) if isinstance(row, dict)]

    for start_index in range(page_size + 1, total_count + 1, page_size):
        end_index = min(start_index + page_size - 1, total_count)
        page_payload = call_seoul_list_api_payload(
            service_name=SERVICE_NAME,
            api_key=api_key,
            start_index=start_index,
            end_index=end_index,
        )
        rows.extend(row for row in page_payload.get("row", []) if isinstance(row, dict))

    return rows


def _build_rows(rows: list[dict], requested_at) -> tuple[list[tuple], list[tuple], Counter]:
    raw_rows: list[tuple] = []
    loaded_rows_by_biz_cd: dict[str, tuple] = {}
    exclusion_reasons: Counter = Counter()

    for source_row_number, row in enumerate(rows, start=1):
        biz_cd = _clean_text(row.get("BIZ_CD"))
        if biz_cd is None:
            exclusion_reason = "missing_biz_cd"
            normalized_district_name = None
            is_loaded = False
        else:
            normalized_district_name = _normalize_district_name(
                row.get("GU_NM"),
                row.get("CSTRN_PSTN"),
                row.get("BIZ_NM"),
                row.get("INST_NM"),
            )
            is_loaded = normalized_district_name is not None
            exclusion_reason = None if is_loaded else "non_seoul_or_unmapped"

        project_name = _clean_text(row.get("BIZ_NM"))
        if is_loaded and project_name is None:
            is_loaded = False
            exclusion_reason = "missing_project_name"

        if not is_loaded:
            exclusion_reasons[exclusion_reason] += 1

        raw_rows.append(
            (
                requested_at,
                SERVICE_NAME,
                source_row_number,
                biz_cd,
                _clean_text(row.get("GU_CD")),
                _clean_text(row.get("GU_NM")),
                normalized_district_name,
                is_loaded,
                exclusion_reason,
                Json(row),
            )
        )

        if not is_loaded or biz_cd is None:
            continue

        completion_status = _normalize_completion_status(row.get("CMCN_YN2"), row.get("CMCN_YN1"))
        normalized_row = {
            "biz_cd": biz_cd,
            "district_name": normalized_district_name,
            "contractor_name": _clean_text(row.get("CNST_ENT")),
            "ordering_agency_name": _clean_text(row.get("INST_NM")),
            "project_name": project_name,
            "completion_status": completion_status,
            "raw_gu_cd": _clean_text(row.get("GU_CD")),
            "raw_gu_name": _clean_text(row.get("GU_NM")),
        }
        source_row_hash = _make_row_hash(normalized_row)
        prepared_row = (
            biz_cd,
            normalized_district_name,
            normalized_row["contractor_name"],
            normalized_row["ordering_agency_name"],
            normalized_row["project_name"],
            completion_status,
            normalized_row["raw_gu_cd"],
            normalized_row["raw_gu_name"],
            source_row_hash,
            Json(row),
            requested_at,
            requested_at,
            requested_at,
        )

        if biz_cd in loaded_rows_by_biz_cd:
            exclusion_reasons["duplicate_biz_cd_in_response"] += 1
        loaded_rows_by_biz_cd[biz_cd] = prepared_row

    return raw_rows, list(loaded_rows_by_biz_cd.values()), exclusion_reasons


def _sync_rows(raw_rows: list[tuple], loaded_rows: list[tuple]) -> None:
    raw_sql = """
    INSERT INTO raw.seoul_construction_progress_raw (
        requested_at,
        source_service_name,
        source_row_number,
        biz_cd,
        raw_gu_cd,
        raw_gu_name,
        normalized_district_name,
        is_loaded,
        exclusion_reason,
        response_json
    )
    VALUES %s
    """

    upsert_sql = """
    INSERT INTO ref.seoul_construction_progress (
        biz_cd,
        district_name,
        contractor_name,
        ordering_agency_name,
        project_name,
        completion_status,
        raw_gu_cd,
        raw_gu_name,
        source_row_hash,
        row_json,
        requested_at,
        created_at,
        updated_at
    )
    VALUES %s
    ON CONFLICT (biz_cd)
    DO UPDATE SET
        district_name = EXCLUDED.district_name,
        contractor_name = EXCLUDED.contractor_name,
        ordering_agency_name = EXCLUDED.ordering_agency_name,
        project_name = EXCLUDED.project_name,
        completion_status = EXCLUDED.completion_status,
        raw_gu_cd = EXCLUDED.raw_gu_cd,
        raw_gu_name = EXCLUDED.raw_gu_name,
        source_row_hash = EXCLUDED.source_row_hash,
        row_json = EXCLUDED.row_json,
        requested_at = EXCLUDED.requested_at,
        updated_at = EXCLUDED.updated_at
    """

    with get_conn() as conn:
        with conn.cursor() as cur:
            if raw_rows:
                execute_values(cur, raw_sql, raw_rows, page_size=1000)

            cur.execute("CREATE TEMP TABLE current_construction_biz_cd (biz_cd TEXT PRIMARY KEY) ON COMMIT DROP")
            if loaded_rows:
                execute_values(cur, upsert_sql, loaded_rows, page_size=1000)
                execute_values(
                    cur,
                    "INSERT INTO current_construction_biz_cd (biz_cd) VALUES %s",
                    [(row[0],) for row in loaded_rows],
                    page_size=1000,
                )
                cur.execute(
                    """
                    DELETE FROM ref.seoul_construction_progress target
                    WHERE NOT EXISTS (
                        SELECT 1
                        FROM current_construction_biz_cd current_rows
                        WHERE current_rows.biz_cd = target.biz_cd
                    )
                    """
                )
            else:
                cur.execute("DELETE FROM ref.seoul_construction_progress")
        conn.commit()


def main() -> None:
    parser = argparse.ArgumentParser(description="Collect Seoul construction progress data.")
    parser.add_argument("--api-key", default=DEFAULT_API_KEY, help="Seoul Open API key.")
    parser.add_argument("--page-size", type=int, default=1000, help="Rows per API request.")
    args = parser.parse_args()

    requested_at = now_kst()
    rows = _fetch_all_rows(api_key=args.api_key, page_size=args.page_size)
    if not rows:
        raise SeoulApiError("No rows returned from Seoul construction progress API")

    raw_rows, loaded_rows, exclusion_reasons = _build_rows(rows, requested_at)
    _sync_rows(raw_rows, loaded_rows)

    total_count = len(rows)
    loaded_count = len(loaded_rows)
    excluded_count = sum(exclusion_reasons.values())
    seoul_filtered_count = total_count - exclusion_reasons.get("missing_biz_cd", 0) - exclusion_reasons.get("non_seoul_or_unmapped", 0)

    print(
        "[seoul_construction_progress] "
        f"requested_at={requested_at.isoformat()} "
        f"total_count={total_count} "
        f"seoul_filtered_count={seoul_filtered_count} "
        f"loaded_count={loaded_count} "
        f"excluded_count={excluded_count}"
    )
    if exclusion_reasons:
        details = ",".join(
            f"{reason}:{count}"
            for reason, count in sorted(exclusion_reasons.items())
        )
        print(f"[seoul_construction_progress] excluded_reasons={details}")


if __name__ == "__main__":
    main()
