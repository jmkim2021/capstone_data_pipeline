from __future__ import annotations

from collections import defaultdict
from datetime import datetime
from typing import TypedDict

from core.kma_time import combine_kst


class PrecipParseResult(TypedDict):
    raw_text: str | None
    numeric_value: float | None
    parse_type: str


def parse_precip_text(value: str | None) -> PrecipParseResult:
    if value is None:
        return {
            "raw_text": None,
            "numeric_value": None,
            "parse_type": "missing",
        }

    value = str(value).strip()

    if value in {"강수없음", "없음", "0", "0mm"}:
        return {
            "raw_text": value,
            "numeric_value": 0.0,
            "parse_type": "none",
        }

    if "미만" in value:
        num = value.replace("mm", "").replace("미만", "").strip()
        try:
            return {
                "raw_text": value,
                "numeric_value": float(num),
                "parse_type": "lt_bound",
            }
        except ValueError:
            return {
                "raw_text": value,
                "numeric_value": None,
                "parse_type": "unparsed",
            }

    if "~" in value:
        left, right = value.split("~", maxsplit=1)
        try:
            left_num = float(left.replace("mm", "").strip())
            right_num = float(right.replace("mm", "").replace("이상", "").strip())
            return {
                "raw_text": value,
                "numeric_value": (left_num + right_num) / 2,
                "parse_type": "range",
            }
        except ValueError:
            return {
                "raw_text": value,
                "numeric_value": None,
                "parse_type": "unparsed",
            }

    if "이상" in value:
        num = value.replace("mm", "").replace("이상", "").strip()
        try:
            return {
                "raw_text": value,
                "numeric_value": float(num),
                "parse_type": "gte_bound",
            }
        except ValueError:
            return {
                "raw_text": value,
                "numeric_value": None,
                "parse_type": "unparsed",
            }

    if "mm" in value:
        try:
            return {
                "raw_text": value,
                "numeric_value": float(value.replace("mm", "").strip()),
                "parse_type": "exact",
            }
        except ValueError:
            return {
                "raw_text": value,
                "numeric_value": None,
                "parse_type": "unparsed",
            }

    try:
        return {
            "raw_text": value,
            "numeric_value": float(value),
            "parse_type": "exact",
        }
    except ValueError:
        return {
            "raw_text": value,
            "numeric_value": None,
            "parse_type": "unparsed",
        }


def parse_precip_text_to_num(value: str | None) -> float | None:
    return parse_precip_text(value)["numeric_value"]


def pivot_ultra_now(items: list[dict], requested_at: datetime) -> list[dict]:
    grouped: dict[tuple[str, str, int, int], dict] = defaultdict(dict)

    for item in items:
        key = (
            item["baseDate"],
            item["baseTime"],
            int(item["nx"]),
            int(item["ny"]),
        )
        grouped[key][item["category"]] = item["obsrValue"]

    rows: list[dict] = []
    for (base_date, base_time, nx, ny), values in grouped.items():
        rain_1h = parse_precip_text(values.get("RN1"))
        rows.append({
            "base_datetime": combine_kst(base_date, base_time),
            "nx": nx,
            "ny": ny,
            "rain_1h_text": rain_1h["raw_text"],
            "rain_1h_mm": rain_1h["numeric_value"],
            "rain_1h_parse_type": rain_1h["parse_type"],
            "temp_c": parse_precip_text_to_num(values.get("T1H")),
            "humidity_pct": parse_precip_text_to_num(values.get("REH")),
            "wind_speed_ms": parse_precip_text_to_num(values.get("WSD")),
            "wind_dir_deg": parse_precip_text_to_num(values.get("VEC")),
            "precip_type_code": values.get("PTY"),
            "requested_at": requested_at,
            "raw_batch_time": requested_at,
        })
    return rows


def pivot_ultra_fcst(items: list[dict], requested_at: datetime) -> list[dict]:
    grouped: dict[tuple[str, str, str, str, int, int], dict] = defaultdict(dict)

    for item in items:
        key = (
            item["baseDate"],
            item["baseTime"],
            item["fcstDate"],
            item["fcstTime"],
            int(item["nx"]),
            int(item["ny"]),
        )
        grouped[key][item["category"]] = item["fcstValue"]

    rows: list[dict] = []
    for (base_date, base_time, fcst_date, fcst_time, nx, ny), values in grouped.items():
        base_dt = combine_kst(base_date, base_time)
        fcst_dt = combine_kst(fcst_date, fcst_time)
        precip = parse_precip_text(values.get("RN1"))

        rows.append({
            "base_datetime": base_dt,
            "forecast_datetime": fcst_dt,
            "lead_minutes": int((fcst_dt - base_dt).total_seconds() // 60),
            "nx": nx,
            "ny": ny,
            "forecast_temp_c": parse_precip_text_to_num(values.get("T1H")),
            "forecast_humidity_pct": parse_precip_text_to_num(values.get("REH")),
            "forecast_sky_code": values.get("SKY"),
            "forecast_precip_type_code": values.get("PTY"),
            "forecast_precip_mm_text": precip["raw_text"],
            "forecast_precip_mm_num": precip["numeric_value"],
            "forecast_precip_parse_type": precip["parse_type"],
            "forecast_wind_speed_ms": parse_precip_text_to_num(values.get("WSD")),
            "requested_at": requested_at,
        })
    return rows


def pivot_short_fcst(items: list[dict], requested_at: datetime) -> list[dict]:
    grouped: dict[tuple[str, str, str, str, int, int], dict] = defaultdict(dict)

    for item in items:
        key = (
            item["baseDate"],
            item["baseTime"],
            item["fcstDate"],
            item["fcstTime"],
            int(item["nx"]),
            int(item["ny"]),
        )
        grouped[key][item["category"]] = item["fcstValue"]

    rows: list[dict] = []
    for (base_date, base_time, fcst_date, fcst_time, nx, ny), values in grouped.items():
        base_dt = combine_kst(base_date, base_time)
        fcst_dt = combine_kst(fcst_date, fcst_time)
        precip = parse_precip_text(values.get("PCP"))

        rows.append({
            "base_datetime": base_dt,
            "forecast_datetime": fcst_dt,
            "lead_hours": int((fcst_dt - base_dt).total_seconds() // 3600),
            "nx": nx,
            "ny": ny,
            "forecast_temp_c": parse_precip_text_to_num(values.get("TMP")),
            "forecast_humidity_pct": parse_precip_text_to_num(values.get("REH")),
            "forecast_pop_pct": parse_precip_text_to_num(values.get("POP")),
            "forecast_precip_mm_text": precip["raw_text"],
            "forecast_precip_mm_num": precip["numeric_value"],
            "forecast_precip_parse_type": precip["parse_type"],
            "forecast_sky_code": values.get("SKY"),
            "forecast_precip_type_code": values.get("PTY"),
            "forecast_wind_speed_ms": parse_precip_text_to_num(values.get("WSD")),
            "requested_at": requested_at,
        })
    return rows