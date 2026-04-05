from __future__ import annotations

from core.api_client import KMAApiError, call_kma
from core.config import settings
from core.db import insert_raw_ultra_now, upsert_district_ultra_now, upsert_std_ultra_now
from core.district_agg import aggregate_ultra_now_by_district
from core.grid_map import load_district_grid_mappings, parse_district_names
from core.kma_time import get_latest_ultra_base_datetime, fmt_date, fmt_time, now_kst
from core.parser import pivot_ultra_now

def main() -> None:
    requested_at = now_kst()
    base_dt = get_latest_ultra_base_datetime(
        requested_at,
        lag_minutes=settings.ultra_now_lag_minutes,
    )

    raw_rows: list[dict] = []
    std_items: list[dict] = []
    district_items: list[dict] = []
    success_grids = 0
    failed_grids: list[tuple[int, int, str]] = []
    district_mappings = load_district_grid_mappings(
        settings.district_grid_mapping_path,
        district_names=parse_district_names(settings.district_names_raw) or None,
    )

    for nx, ny in settings.target_grids:
        try:
            items = call_kma(
                endpoint="getUltraSrtNcst",
                base_date=fmt_date(base_dt),
                base_time=fmt_time(base_dt),
                nx=nx,
                ny=ny,
            )
        except KMAApiError as exc:
            failed_grids.append((nx, ny, str(exc)))
            continue

        for item in items:
            raw_rows.append({
                "requested_at": requested_at,
                "base_date": item["baseDate"],
                "base_time": item["baseTime"],
                "nx": int(item["nx"]),
                "ny": int(item["ny"]),
                "category": item["category"],
                "obsr_value": item["obsrValue"],
                "response_json": item,
            })

        std_items.extend(pivot_ultra_now(items, requested_at=requested_at))
        success_grids += 1

    if raw_rows:
        insert_raw_ultra_now(raw_rows)
    if std_items:
        upsert_std_ultra_now(std_items)
    if district_mappings and std_items:
        district_items = aggregate_ultra_now_by_district(std_items, district_mappings)
        if district_items:
            upsert_district_ultra_now(district_items)

    print(
        "[ultra_now] "
        f"requested_at={requested_at.isoformat()} "
        f"base_dt={base_dt.isoformat()} "
        f"success_grids={success_grids} "
        f"failed_grids={len(failed_grids)} "
        f"raw={len(raw_rows)} std={len(std_items)} district={len(district_items)}"
    )
    for nx, ny, error in failed_grids:
        print(f"[ultra_now][failed_grid] nx={nx} ny={ny} error={error}")


if __name__ == "__main__":
    main()