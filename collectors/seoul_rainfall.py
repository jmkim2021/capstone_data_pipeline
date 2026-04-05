from __future__ import annotations

from datetime import datetime
from pathlib import Path
import sys

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.append(str(PROJECT_ROOT))

from core.config import settings
from core.db import (
    insert_raw_seoul_rainfall,
    upsert_mart_seoul_rainfall_district_latest,
    upsert_std_seoul_rainfall,
)
from core.kma_time import now_kst
from core.seoul_api import SeoulApiError, call_seoul_list_api


SERVICE_NAME = "ListRainfallService"


def _parse_observed_at(value: str) -> datetime:
    return datetime.strptime(value, "%Y-%m-%d %H:%M").replace(tzinfo=now_kst().tzinfo)


def main() -> None:
    requested_at = now_kst()
    rows = call_seoul_list_api(
        service_name=SERVICE_NAME,
        api_key=settings.seoul_rainfall_api_key,
        start_index=1,
        end_index=settings.seoul_api_page_size,
    )
    if not rows:
        raise SeoulApiError("No rows returned from Seoul rainfall API")

    latest_observed_text = max(str(row["DATA_CLCT_TM"]) for row in rows if row.get("DATA_CLCT_TM"))
    latest_rows = [row for row in rows if str(row.get("DATA_CLCT_TM")) == latest_observed_text]

    raw_rows: list[dict] = []
    std_rows: list[dict] = []
    district_map: dict[tuple[datetime, str], dict] = {}

    for row in latest_rows:
        observed_at = _parse_observed_at(str(row["DATA_CLCT_TM"]))
        station_code = int(float(row["RF_CD"]))
        district_name = str(row.get("GU_NM") or "").strip() or None
        district_code_raw = row.get("GU_CD")
        district_code = int(float(district_code_raw)) if district_code_raw not in (None, "") else None
        rain_10m_mm = float(row["RN_10M"]) if row.get("RN_10M") not in (None, "") else None

        raw_rows.append({
            "requested_at": requested_at,
            "observed_at": observed_at,
            "station_code": station_code,
            "response_json": row,
        })
        std_rows.append({
            "observed_at": observed_at,
            "station_code": station_code,
            "station_name": str(row.get("RF_NM") or "").strip(),
            "district_code": district_code,
            "district_name": district_name,
            "rain_10m_mm": rain_10m_mm,
            "requested_at": requested_at,
        })

        if district_name is None:
            continue
        key = (observed_at, district_name)
        item = district_map.setdefault(key, {
            "observed_at": observed_at,
            "district_name": district_name,
            "station_count": 0,
            "rain_values": [],
            "requested_at": requested_at,
        })
        item["station_count"] += 1
        if rain_10m_mm is not None:
            item["rain_values"].append(rain_10m_mm)

    district_rows = []
    for item in district_map.values():
        values = item["rain_values"]
        district_rows.append({
            "observed_at": item["observed_at"],
            "district_name": item["district_name"],
            "station_count": item["station_count"],
            "avg_rain_10m_mm": (sum(values) / len(values)) if values else None,
            "max_rain_10m_mm": max(values) if values else None,
            "requested_at": item["requested_at"],
        })

    insert_raw_seoul_rainfall(raw_rows)
    upsert_std_seoul_rainfall(std_rows)
    if district_rows:
        upsert_mart_seoul_rainfall_district_latest(district_rows)

    print(
        "[seoul_rainfall] "
        f"requested_at={requested_at.isoformat()} "
        f"observed_at={latest_observed_text} "
        f"stations={len(std_rows)} district={len(district_rows)}"
    )


if __name__ == "__main__":
    main()
