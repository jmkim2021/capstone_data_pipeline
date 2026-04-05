from __future__ import annotations

from collections import defaultdict

from core.grid_map import DistrictGridMapping


def _weighted_average(sum_value: float, sum_weight: float) -> float | None:
    if sum_weight <= 0:
        return None
    return sum_value / sum_weight


def aggregate_ultra_now_by_district(
    std_rows: list[dict],
    mappings: list[DistrictGridMapping],
) -> list[dict]:
    mappings_by_grid: dict[tuple[int, int], list[DistrictGridMapping]] = defaultdict(list)
    for mapping in mappings:
        mappings_by_grid[(mapping.nx, mapping.ny)].append(mapping)

    grouped: dict[tuple[object, str], dict] = {}

    for row in std_rows:
        grid_mappings = mappings_by_grid.get((row["nx"], row["ny"]), [])
        if not grid_mappings:
            continue

        for mapping in grid_mappings:
            key = (row["base_datetime"], mapping.district_name)
            if key not in grouped:
                grouped[key] = {
                    "base_datetime": row["base_datetime"],
                    "district_name": mapping.district_name,
                    "requested_at": row["requested_at"],
                    "raw_batch_time": row["raw_batch_time"],
                    "rain_1h_weighted_sum": 0.0,
                    "rain_1h_weight_sum": 0.0,
                    "temp_weighted_sum": 0.0,
                    "temp_weight_sum": 0.0,
                    "humidity_weighted_sum": 0.0,
                    "humidity_weight_sum": 0.0,
                    "wind_speed_weighted_sum": 0.0,
                    "wind_speed_weight_sum": 0.0,
                    "wind_dir_weighted_sum": 0.0,
                    "wind_dir_weight_sum": 0.0,
                    "precip_type_code": None,
                    "source_grid_count": 0,
                    "weight_sum": 0.0,
                }

            agg = grouped[key]
            weight = mapping.weight
            agg["source_grid_count"] += 1
            agg["weight_sum"] += weight

            for value_key, sum_key, weight_key in [
                ("rain_1h_mm", "rain_1h_weighted_sum", "rain_1h_weight_sum"),
                ("temp_c", "temp_weighted_sum", "temp_weight_sum"),
                ("humidity_pct", "humidity_weighted_sum", "humidity_weight_sum"),
                ("wind_speed_ms", "wind_speed_weighted_sum", "wind_speed_weight_sum"),
                ("wind_dir_deg", "wind_dir_weighted_sum", "wind_dir_weight_sum"),
            ]:
                value = row.get(value_key)
                if value is None:
                    continue
                agg[sum_key] += value * weight
                agg[weight_key] += weight

            precip_type_code = row.get("precip_type_code")
            if precip_type_code is not None:
                current_code = agg["precip_type_code"]
                if current_code is None or str(precip_type_code) > str(current_code):
                    agg["precip_type_code"] = precip_type_code

    district_rows: list[dict] = []
    for agg in grouped.values():
        district_rows.append({
            "base_datetime": agg["base_datetime"],
            "district_name": agg["district_name"],
            "rain_1h_mm": _weighted_average(agg["rain_1h_weighted_sum"], agg["rain_1h_weight_sum"]),
            "temp_c": _weighted_average(agg["temp_weighted_sum"], agg["temp_weight_sum"]),
            "humidity_pct": _weighted_average(agg["humidity_weighted_sum"], agg["humidity_weight_sum"]),
            "wind_speed_ms": _weighted_average(
                agg["wind_speed_weighted_sum"],
                agg["wind_speed_weight_sum"],
            ),
            "wind_dir_deg": _weighted_average(
                agg["wind_dir_weighted_sum"],
                agg["wind_dir_weight_sum"],
            ),
            "precip_type_code": agg["precip_type_code"],
            "source_grid_count": agg["source_grid_count"],
            "weight_sum": agg["weight_sum"],
            "requested_at": agg["requested_at"],
            "raw_batch_time": agg["raw_batch_time"],
        })

    district_rows.sort(key=lambda row: (row["district_name"], row["base_datetime"]))
    return district_rows


def aggregate_ultra_fcst_by_district(
    std_rows: list[dict],
    mappings: list[DistrictGridMapping],
) -> list[dict]:
    mappings_by_grid: dict[tuple[int, int], list[DistrictGridMapping]] = defaultdict(list)
    for mapping in mappings:
        mappings_by_grid[(mapping.nx, mapping.ny)].append(mapping)

    grouped: dict[tuple[object, object, str], dict] = {}

    for row in std_rows:
        grid_mappings = mappings_by_grid.get((row["nx"], row["ny"]), [])
        if not grid_mappings:
            continue

        for mapping in grid_mappings:
            key = (row["base_datetime"], row["forecast_datetime"], mapping.district_name)
            if key not in grouped:
                grouped[key] = {
                    "base_datetime": row["base_datetime"],
                    "forecast_datetime": row["forecast_datetime"],
                    "lead_minutes": row["lead_minutes"],
                    "district_name": mapping.district_name,
                    "requested_at": row["requested_at"],
                    "forecast_temp_weighted_sum": 0.0,
                    "forecast_temp_weight_sum": 0.0,
                    "forecast_humidity_weighted_sum": 0.0,
                    "forecast_humidity_weight_sum": 0.0,
                    "forecast_precip_weighted_sum": 0.0,
                    "forecast_precip_weight_sum": 0.0,
                    "forecast_wind_weighted_sum": 0.0,
                    "forecast_wind_weight_sum": 0.0,
                    "forecast_sky_code": None,
                    "forecast_precip_type_code": None,
                    "source_grid_count": 0,
                    "weight_sum": 0.0,
                }

            agg = grouped[key]
            weight = mapping.weight
            agg["source_grid_count"] += 1
            agg["weight_sum"] += weight

            for value_key, sum_key, weight_key in [
                ("forecast_temp_c", "forecast_temp_weighted_sum", "forecast_temp_weight_sum"),
                (
                    "forecast_humidity_pct",
                    "forecast_humidity_weighted_sum",
                    "forecast_humidity_weight_sum",
                ),
                (
                    "forecast_precip_mm_num",
                    "forecast_precip_weighted_sum",
                    "forecast_precip_weight_sum",
                ),
                ("forecast_wind_speed_ms", "forecast_wind_weighted_sum", "forecast_wind_weight_sum"),
            ]:
                value = row.get(value_key)
                if value is None:
                    continue
                agg[sum_key] += value * weight
                agg[weight_key] += weight

            for code_key in ["forecast_sky_code", "forecast_precip_type_code"]:
                code_value = row.get(code_key)
                if code_value is None:
                    continue
                current_value = agg[code_key]
                if current_value is None or str(code_value) > str(current_value):
                    agg[code_key] = code_value

    district_rows: list[dict] = []
    for agg in grouped.values():
        district_rows.append({
            "base_datetime": agg["base_datetime"],
            "forecast_datetime": agg["forecast_datetime"],
            "lead_minutes": agg["lead_minutes"],
            "district_name": agg["district_name"],
            "forecast_temp_c": _weighted_average(
                agg["forecast_temp_weighted_sum"],
                agg["forecast_temp_weight_sum"],
            ),
            "forecast_humidity_pct": _weighted_average(
                agg["forecast_humidity_weighted_sum"],
                agg["forecast_humidity_weight_sum"],
            ),
            "forecast_precip_mm_num": _weighted_average(
                agg["forecast_precip_weighted_sum"],
                agg["forecast_precip_weight_sum"],
            ),
            "forecast_wind_speed_ms": _weighted_average(
                agg["forecast_wind_weighted_sum"],
                agg["forecast_wind_weight_sum"],
            ),
            "forecast_sky_code": agg["forecast_sky_code"],
            "forecast_precip_type_code": agg["forecast_precip_type_code"],
            "source_grid_count": agg["source_grid_count"],
            "weight_sum": agg["weight_sum"],
            "requested_at": agg["requested_at"],
        })

    district_rows.sort(
        key=lambda row: (row["district_name"], row["base_datetime"], row["forecast_datetime"])
    )
    return district_rows


def aggregate_short_fcst_by_district(
    std_rows: list[dict],
    mappings: list[DistrictGridMapping],
) -> list[dict]:
    mappings_by_grid: dict[tuple[int, int], list[DistrictGridMapping]] = defaultdict(list)
    for mapping in mappings:
        mappings_by_grid[(mapping.nx, mapping.ny)].append(mapping)

    grouped: dict[tuple[object, object, str], dict] = {}

    for row in std_rows:
        grid_mappings = mappings_by_grid.get((row["nx"], row["ny"]), [])
        if not grid_mappings:
            continue

        for mapping in grid_mappings:
            key = (row["base_datetime"], row["forecast_datetime"], mapping.district_name)
            if key not in grouped:
                grouped[key] = {
                    "base_datetime": row["base_datetime"],
                    "forecast_datetime": row["forecast_datetime"],
                    "lead_hours": row["lead_hours"],
                    "district_name": mapping.district_name,
                    "requested_at": row["requested_at"],
                    "forecast_temp_weighted_sum": 0.0,
                    "forecast_temp_weight_sum": 0.0,
                    "forecast_humidity_weighted_sum": 0.0,
                    "forecast_humidity_weight_sum": 0.0,
                    "forecast_pop_weighted_sum": 0.0,
                    "forecast_pop_weight_sum": 0.0,
                    "forecast_precip_weighted_sum": 0.0,
                    "forecast_precip_weight_sum": 0.0,
                    "forecast_wind_weighted_sum": 0.0,
                    "forecast_wind_weight_sum": 0.0,
                    "forecast_sky_code": None,
                    "forecast_precip_type_code": None,
                    "source_grid_count": 0,
                    "weight_sum": 0.0,
                }

            agg = grouped[key]
            weight = mapping.weight
            agg["source_grid_count"] += 1
            agg["weight_sum"] += weight

            for value_key, sum_key, weight_key in [
                ("forecast_temp_c", "forecast_temp_weighted_sum", "forecast_temp_weight_sum"),
                (
                    "forecast_humidity_pct",
                    "forecast_humidity_weighted_sum",
                    "forecast_humidity_weight_sum",
                ),
                ("forecast_pop_pct", "forecast_pop_weighted_sum", "forecast_pop_weight_sum"),
                (
                    "forecast_precip_mm_num",
                    "forecast_precip_weighted_sum",
                    "forecast_precip_weight_sum",
                ),
                ("forecast_wind_speed_ms", "forecast_wind_weighted_sum", "forecast_wind_weight_sum"),
            ]:
                value = row.get(value_key)
                if value is None:
                    continue
                agg[sum_key] += value * weight
                agg[weight_key] += weight

            for code_key in ["forecast_sky_code", "forecast_precip_type_code"]:
                code_value = row.get(code_key)
                if code_value is None:
                    continue
                current_value = agg[code_key]
                if current_value is None or str(code_value) > str(current_value):
                    agg[code_key] = code_value

    district_rows: list[dict] = []
    for agg in grouped.values():
        district_rows.append({
            "base_datetime": agg["base_datetime"],
            "forecast_datetime": agg["forecast_datetime"],
            "lead_hours": agg["lead_hours"],
            "district_name": agg["district_name"],
            "forecast_temp_c": _weighted_average(
                agg["forecast_temp_weighted_sum"],
                agg["forecast_temp_weight_sum"],
            ),
            "forecast_humidity_pct": _weighted_average(
                agg["forecast_humidity_weighted_sum"],
                agg["forecast_humidity_weight_sum"],
            ),
            "forecast_pop_pct": _weighted_average(
                agg["forecast_pop_weighted_sum"],
                agg["forecast_pop_weight_sum"],
            ),
            "forecast_precip_mm_num": _weighted_average(
                agg["forecast_precip_weighted_sum"],
                agg["forecast_precip_weight_sum"],
            ),
            "forecast_wind_speed_ms": _weighted_average(
                agg["forecast_wind_weighted_sum"],
                agg["forecast_wind_weight_sum"],
            ),
            "forecast_sky_code": agg["forecast_sky_code"],
            "forecast_precip_type_code": agg["forecast_precip_type_code"],
            "source_grid_count": agg["source_grid_count"],
            "weight_sum": agg["weight_sum"],
            "requested_at": agg["requested_at"],
        })

    district_rows.sort(
        key=lambda row: (row["district_name"], row["base_datetime"], row["forecast_datetime"])
    )
    return district_rows
