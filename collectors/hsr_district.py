from __future__ import annotations

from datetime import timedelta
from pathlib import Path
import sys

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.append(str(PROJECT_ROOT))

from core.config import settings
from core.db import insert_raw_hsr_area, upsert_std_hsr_area_district
from core.hsr_api import HSRApiError, call_hsr_area
from core.kma_time import now_kst

SEOUL_DISTRICTS = {
    "종로구": "1111000000",
    "중구": "1114000000",
    "용산구": "1117000000",
    "성동구": "1120000000",
    "광진구": "1121500000",
    "동대문구": "1123000000",
    "중랑구": "1126000000",
    "성북구": "1129000000",
    "강북구": "1130500000",
    "도봉구": "1132000000",
    "노원구": "1135000000",
    "은평구": "1138000000",
    "서대문구": "1141000000",
    "마포구": "1144000000",
    "양천구": "1147000000",
    "강서구": "1150000000",
    "구로구": "1153000000",
    "금천구": "1154500000",
    "영등포구": "1156000000",
    "동작구": "1159000000",
    "관악구": "1162000000",
    "서초구": "1165000000",
    "강남구": "1168000000",
    "송파구": "1171000000",
    "강동구": "1174000000",
}
SEOUL_CITY_CODE = "1100000000"


def _floor_to_5min(dt):
    minute = (dt.minute // 5) * 5
    return dt.replace(minute=minute, second=0, microsecond=0)


def _parse_float(value: str | None) -> float | None:
    if value in (None, ""):
        return None
    try:
        return float(value)
    except ValueError:
        return None


def _find_latest_available_base_datetime(requested_at):
    candidate = _floor_to_5min(requested_at - timedelta(minutes=settings.hsr_lag_minutes))
    for _ in range(settings.hsr_area_lookback_steps):
        try:
            call_hsr_area(
                candidate.strftime("%Y%m%d%H%M"),
                SEOUL_CITY_CODE,
                comp_type=settings.hsr_area_comp_type,
                data_type_cd=settings.hsr_area_data_type_cd,
            )
            return candidate
        except HSRApiError as exc:
            if "no data" not in str(exc).lower():
                raise
            candidate -= timedelta(minutes=5)
    raise HSRApiError("HSR area API returned no data within lookback window")


def main() -> None:
    requested_at = now_kst()
    base_dt = _find_latest_available_base_datetime(requested_at)

    raw_rows = []
    std_rows = []
    failed = []

    for district_name, district_code in SEOUL_DISTRICTS.items():
        try:
            payload, items, http_status = call_hsr_area(
                base_dt.strftime("%Y%m%d%H%M"),
                district_code,
                comp_type=settings.hsr_area_comp_type,
                data_type_cd=settings.hsr_area_data_type_cd,
            )
            header = payload.get("response", {}).get("header", {})
            raw_rows.append({
                "requested_at": requested_at,
                "base_datetime": base_dt,
                "district_code": district_code,
                "district_name": district_name,
                "comp_type": settings.hsr_area_comp_type,
                "data_type_cd": settings.hsr_area_data_type_cd,
                "http_status": http_status,
                "result_code": str(header.get("resultCode", "")),
                "is_success": True,
                "error_message": None,
                "response_json": payload,
            })

            if not items:
                failed.append(district_name)
                continue

            item = items[0]
            value_numeric = _parse_float(item.get("value"))
            std_rows.append({
                "base_datetime": base_dt,
                "district_code": district_code,
                "district_name": district_name,
                "comp_type": settings.hsr_area_comp_type,
                "data_type_cd": settings.hsr_area_data_type_cd,
                "lon": _parse_float(item.get("lon")),
                "lat": _parse_float(item.get("lat")),
                "unit": item.get("unit"),
                "value_numeric": value_numeric,
                "raw_value_text": item.get("value"),
                "is_no_echo": value_numeric is not None and value_numeric <= -200.0,
                "requested_at": requested_at,
            })
        except HSRApiError as exc:
            failed.append(district_name)
            raw_rows.append({
                "requested_at": requested_at,
                "base_datetime": base_dt,
                "district_code": district_code,
                "district_name": district_name,
                "comp_type": settings.hsr_area_comp_type,
                "data_type_cd": settings.hsr_area_data_type_cd,
                "http_status": None,
                "result_code": None,
                "is_success": False,
                "error_message": str(exc),
                "response_json": None,
            })

    insert_raw_hsr_area(raw_rows)
    upsert_std_hsr_area_district(std_rows)

    print(
        "[hsr_district] "
        f"requested_at={requested_at.isoformat()} "
        f"base_dt={base_dt.isoformat()} "
        f"district_success={len(std_rows)} "
        f"district_failed={len(failed)}"
    )
    if failed:
        print("[hsr_district] failed_districts=" + ",".join(failed))


if __name__ == "__main__":
    main()
