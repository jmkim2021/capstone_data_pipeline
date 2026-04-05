from __future__ import annotations

from datetime import datetime
from pathlib import Path
import sys

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.append(str(PROJECT_ROOT))

from core.config import settings
from core.db import (
    insert_raw_seoul_river_stage,
    upsert_mart_seoul_river_stage_latest,
    upsert_std_seoul_river_stage,
)
from core.kma_time import now_kst
from core.seoul_api import SeoulApiError, call_seoul_list_api


SERVICE_NAME = "ListRiverStageService"


def _parse_dt(value: str) -> datetime:
    return datetime.strptime(value, "%Y-%m-%d %H:%M:%S").replace(tzinfo=now_kst().tzinfo)


def _to_float(value: object) -> float | None:
    if value in (None, ""):
        return None
    return float(value)


def main() -> None:
    requested_at = now_kst()
    rows = call_seoul_list_api(
        service_name=SERVICE_NAME,
        api_key=settings.seoul_river_api_key,
        start_index=1,
        end_index=100,
    )
    if not rows:
        raise SeoulApiError("No rows returned from Seoul river stage API")

    raw_rows: list[dict] = []
    std_rows: list[dict] = []
    district_map: dict[tuple[datetime, str], dict] = {}

    for row in rows:
        observed_at = _parse_dt(str(row["DTRSM_DATA_CLCT_TM"]))
        observed_minute = observed_at.replace(second=0, microsecond=0)
        server_stored_at = _parse_dt(str(row["RCPTN_SRVR_STRG_TM"])) if row.get("RCPTN_SRVR_STRG_TM") else None
        station_code = str(row["WATG_CD"]).strip()
        district_name = str(row.get("GU_OFC_NM") or "").strip() or None

        water_level_m = _to_float(row.get("RLTM_RVR_WATL_CNT"))
        control_level_m = _to_float(row.get("CNTRL_WATL"))

        raw_rows.append({
            "requested_at": requested_at,
            "observed_at": observed_at,
            "station_code": station_code,
            "response_json": row,
        })
        std_rows.append({
            "observed_at": observed_at,
            "station_code": station_code,
            "station_name": str(row.get("WATG_NM") or "").strip(),
            "river_name": str(row.get("RVR_NM") or "").strip() or None,
            "district_code": str(row.get("STDG_SGG_CD") or "").strip() or None,
            "district_name": district_name,
            "water_level_m": water_level_m,
            "embankment_height_m": _to_float(row.get("EBM_HGT")),
            "plan_flood_level_m": _to_float(row.get("PLAN_FLDE")),
            "riverbed_height_m": _to_float(row.get("RBH")),
            "control_level_m": control_level_m,
            "requested_at": requested_at,
            "server_stored_at": server_stored_at,
        })

        if district_name is None:
            continue
        key = (observed_minute, district_name)
        item = district_map.setdefault(key, {
            "observed_minute": observed_minute,
            "district_name": district_name,
            "station_count": 0,
            "water_levels": [],
            "control_levels": [],
            "requested_at": requested_at,
        })
        item["station_count"] += 1
        if water_level_m is not None:
            item["water_levels"].append(water_level_m)
        if control_level_m is not None:
            item["control_levels"].append(control_level_m)

    district_rows = []
    for item in district_map.values():
        water_levels = item["water_levels"]
        control_levels = item["control_levels"]
        district_rows.append({
            "observed_minute": item["observed_minute"],
            "district_name": item["district_name"],
            "station_count": item["station_count"],
            "avg_water_level_m": (sum(water_levels) / len(water_levels)) if water_levels else None,
            "max_water_level_m": max(water_levels) if water_levels else None,
            "max_control_level_m": max(control_levels) if control_levels else None,
            "requested_at": item["requested_at"],
        })

    insert_raw_seoul_river_stage(raw_rows)
    upsert_std_seoul_river_stage(std_rows)
    if district_rows:
        upsert_mart_seoul_river_stage_latest(district_rows)

    print(
        "[seoul_river_stage] "
        f"requested_at={requested_at.isoformat()} "
        f"stations={len(std_rows)} district={len(district_rows)}"
    )


if __name__ == "__main__":
    main()
