from __future__ import annotations

import argparse
import csv
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.append(str(PROJECT_ROOT))

from core.config import settings
from core.db import upsert_district_ultra_now, upsert_std_ultra_now
from core.district_agg import aggregate_ultra_now_by_district
from core.grid_map import load_district_grid_mappings
from core.parser import parse_precip_text

KST = ZoneInfo("Asia/Seoul")


def _parse_float(value: object) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    s = str(value).strip()
    if s == "" or s.lower() in {"nan", "none", "-"}:
        return None
    try:
        return float(s)
    except ValueError:
        return None


def _parse_datetime_kst(value: str) -> datetime:
    s = (value or "").strip()
    if not s:
        raise ValueError("empty datetime string")

    # isoformat like: 2026-03-26 20:00:00+09:00 or 2026-03-26T20:00:00
    try:
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            return dt.replace(tzinfo=KST)
        return dt.astimezone(KST)
    except ValueError:
        pass

    # common patterns without tzinfo
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y%m%d%H%M", "%Y%m%d%H%M%S"):
        try:
            dt = datetime.strptime(s, fmt)
            return dt.replace(tzinfo=KST)
        except ValueError:
            continue

    raise ValueError(f"Unsupported datetime format: {value!r}")


def _parse_int_or_none(value: object) -> int | None:
    f = _parse_float(value)
    if f is None:
        return None
    return int(f)


def _read_mapping_csv(mapping_path: Path) -> tuple[dict[str, tuple[int, int]], dict[str, tuple[int, int]]]:
    """
    returns:
      - representative_dong -> (nx, ny)
      - district_name -> (nx, ny)
    """
    rep_map: dict[str, tuple[int, int]] = {}
    district_map: dict[str, tuple[int, int]] = {}

    with mapping_path.open("r", encoding="utf-8-sig", newline="") as fp:
        reader = csv.DictReader(fp)
        required = {"district_name", "representative_dong", "nx", "ny"}
        if reader.fieldnames is None or not required.issubset(reader.fieldnames):
            raise ValueError(
                f"{mapping_path} must include columns: {sorted(required)}; got: {reader.fieldnames}"
            )

        for row in reader:
            district_name = (row.get("district_name") or "").strip()
            rep = (row.get("representative_dong") or "").strip()
            if not district_name or not rep:
                continue
            nx = int(float(row["nx"]))
            ny = int(float(row["ny"]))
            district_map[district_name] = (nx, ny)
            rep_map[rep] = (nx, ny)

    return rep_map, district_map


def _detect_column(row: dict[str, object], candidates: list[str]) -> str | None:
    normalized = {str(k).strip(): k for k in row.keys()}
    for c in candidates:
        if c in row:
            return c
        # sometimes the CSV has no exact match due to whitespace
        if c in normalized:
            return normalized[c]
    return None


def _first_present(row: dict[str, object], candidates: list[str]) -> object | None:
    for c in candidates:
        if c in row and row[c] not in (None, ""):
            return row[c]
    return None


@dataclass(frozen=True)
class UltraNowStdRow:
    base_datetime: datetime
    nx: int
    ny: int
    rain_1h_text: str | None
    rain_1h_mm: float | None
    rain_1h_parse_type: str | None
    temp_c: float | None
    humidity_pct: float | None
    wind_speed_ms: float | None
    wind_dir_deg: float | None
    precip_type_code: int | None
    requested_at: datetime
    raw_batch_time: datetime


def _build_std_row_from_portal_csv(
    row: dict[str, object],
    *,
    rep_map: dict[str, tuple[int, int]],
    district_map: dict[str, tuple[int, int]],
    requested_at_default: datetime,
) -> UltraNowStdRow:
    # --- district/grid mapping key ---
    district_col = _detect_column(row, ["district_name", "구", "자치구", "district", "행정구역", "구별"])
    rep_col = _detect_column(row, ["representative_dong", "representativeDong", "대표동", "대표 행정동", "법정동", "dong"])

    nx: int
    ny: int
    mapped = False
    if district_col and row.get(district_col) not in (None, ""):
        district_name = str(row[district_col]).strip()
        if district_name in district_map:
            nx, ny = district_map[district_name]
            mapped = True
    if not mapped and rep_col and row.get(rep_col) not in (None, ""):
        rep = str(row[rep_col]).strip()
        if rep in rep_map:
            nx, ny = rep_map[rep]
            mapped = True

    if not mapped:
        raise ValueError(
            "Could not map portal row to (nx, ny). "
            "Need one of representative_dong/district_name columns, and their values must match "
            f"data/seoul_district_grids.csv. row_keys={list(row.keys())}"
        )

    # --- base_datetime ---
    base_dt_col = _detect_column(row, ["base_datetime", "기준시각", "baseTimeDatetime", "baseTime", "base_datetime_kst"])
    if base_dt_col and row.get(base_dt_col) not in (None, ""):
        base_datetime = _parse_datetime_kst(str(row[base_dt_col]))
    else:
        base_date_col = _detect_column(row, ["base_date", "baseDate", "기준일자", "기준일", "기준날짜"])
        base_time_col = _detect_column(row, ["base_time", "baseTime", "기준시간", "기준 시각", "기준시각시간"])
        if not base_date_col or not base_time_col or row.get(base_date_col) in (None, "") or row.get(base_time_col) in (None, ""):
            raise ValueError(
                "Could not parse base_datetime. Need either column `base_datetime/기준시각` "
                "or both `base_date/baseDate` + `base_time/baseTime`."
            )

        date_str = str(row[base_date_col]).strip()
        time_str = str(row[base_time_col]).strip()

        # normalize date: YYYY-MM-DD or YYYYMMDD
        if "-" in date_str:
            dt_base = datetime.strptime(date_str, "%Y-%m-%d").date()
        else:
            dt_base = datetime.strptime(date_str, "%Y%m%d").date()

        # normalize time: HHMM or HH:MM
        if ":" in time_str:
            dt_time = datetime.strptime(time_str, "%H:%M").time()
        else:
            dt_time = datetime.strptime(time_str, "%H%M").time()

        base_datetime = datetime.combine(dt_base, dt_time).replace(tzinfo=KST)

    # --- requested_at / raw_batch_time (optional) ---
    requested_at: datetime = requested_at_default
    raw_batch_time: datetime = requested_at_default
    for cand in ["requested_at", "수집시각", "loaded_at", "적재시각", "exported_at"]:
        if cand in row and row[cand] not in (None, ""):
            requested_at = _parse_datetime_kst(str(row[cand]))
            raw_batch_time = requested_at
            break

    # --- precipitation (RN1) ---
    # Prefer raw text column for better parse_type.
    rain_text_raw = _first_present(row, ["rain_1h_text", "RN1", "강수량(1시간)", "강수량", "RN1(mm)"])
    rain_mm_raw = _first_present(row, ["rain_1h_mm", "rain1h_mm", "RN1_mm", "RN1(mm)", "강수량(mm)"])

    rain_1h_text: str | None = None
    rain_1h_mm: float | None = None
    rain_1h_parse_type: str | None = None

    if rain_text_raw not in (None, ""):
        parsed = parse_precip_text(str(rain_text_raw))
        rain_1h_text = parsed["raw_text"]
        rain_1h_mm = parsed["numeric_value"]
        rain_1h_parse_type = parsed["parse_type"]
    elif rain_mm_raw not in (None, ""):
        rain_1h_mm = _parse_float(rain_mm_raw)
        rain_1h_text = str(rain_1h_mm) if rain_1h_mm is not None else None
        rain_1h_parse_type = "exact"

    # --- other variables (T1H/REH/WSD/VEC/PTY) ---
    temp_c = _parse_float(_first_present(row, ["temp_c", "T1H", "기온(°C)", "기온"]))
    humidity_pct = _parse_float(_first_present(row, ["humidity_pct", "REH", "습도(%)", "습도"]))
    wind_speed_ms = _parse_float(_first_present(row, ["wind_speed_ms", "WSD", "풍속(m/s)", "풍속"]))
    wind_dir_deg = _parse_float(_first_present(row, ["wind_dir_deg", "VEC", "풍향(deg)", "풍향"]))
    precip_type_code = _parse_int_or_none(_first_present(row, ["precip_type_code", "PTY", "강수형태", "PTY_CODE", "PTY번호"]))

    return UltraNowStdRow(
        base_datetime=base_datetime,
        nx=nx,
        ny=ny,
        rain_1h_text=rain_1h_text,
        rain_1h_mm=rain_1h_mm,
        rain_1h_parse_type=rain_1h_parse_type,
        temp_c=temp_c,
        humidity_pct=humidity_pct,
        wind_speed_ms=wind_speed_ms,
        wind_dir_deg=wind_dir_deg,
        precip_type_code=precip_type_code,
        requested_at=requested_at,
        raw_batch_time=raw_batch_time,
    )


def iter_csv_dicts(path: Path):
    last_exc: Exception | None = None
    for enc in ("utf-8-sig", "cp949", "euc-kr"):
        try:
            with path.open("r", encoding=enc, newline="") as fp:
                reader = csv.DictReader(fp)
                for row in reader:
                    yield row
            return
        except UnicodeDecodeError as exc:
            last_exc = exc
            continue

    raise UnicodeDecodeError(
        "unknown",
        b"",
        0,
        1,
        f"Failed to decode {path}. Tried utf-8-sig/cp949/euc-kr. last_exc={last_exc}",
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Load representative-dong ultra_now portal CSV into std.kma_ultra_now_std (+ mart.seoul_district_ultra_now)."
    )
    parser.add_argument(
        "--input",
        nargs="+",
        type=Path,
        required=True,
        help="Representative-dong ultra_now CSV paths (one or more files).",
    )
    parser.add_argument(
        "--requested-at",
        type=str,
        default="",
        help="Optional override for requested_at/raw_batch_time (ISO or 'YYYY-MM-DD HH:MM'). Default: now(KST).",
    )
    parser.add_argument(
        "--mapping-csv",
        type=Path,
        default=Path(settings.district_grid_mapping_path),
        help="Mapping CSV with district_name/representative_dong/nx/ny. Default: data/seoul_district_grids.csv",
    )
    args = parser.parse_args()

    input_paths: list[Path] = [p.resolve() for p in args.input]
    for p in input_paths:
        if not p.exists():
            raise FileNotFoundError(p)

    requested_at_default = datetime.now(KST)
    if args.requested_at:
        requested_at_default = _parse_datetime_kst(args.requested_at)

    rep_map, district_map = _read_mapping_csv(args.mapping_csv)
    mappings = load_district_grid_mappings(str(args.mapping_csv))

    # dedupe within input by (base_datetime, nx, ny)
    std_dedup: dict[tuple[datetime, int, int], UltraNowStdRow] = {}

    total_rows = 0
    skipped = 0
    for path in input_paths:
        for row in iter_csv_dicts(path):
            total_rows += 1
            try:
                std_row = _build_std_row_from_portal_csv(
                    row,
                    rep_map=rep_map,
                    district_map=district_map,
                    requested_at_default=requested_at_default,
                )
            except Exception:
                skipped += 1
                continue
            key = (std_row.base_datetime, std_row.nx, std_row.ny)
            # if duplicates exist, keep the first one (values should be identical for same grid).
            if key not in std_dedup:
                std_dedup[key] = std_row

    std_rows = [
        {
            "base_datetime": r.base_datetime,
            "nx": r.nx,
            "ny": r.ny,
            "rain_1h_text": r.rain_1h_text,
            "rain_1h_mm": r.rain_1h_mm,
            "rain_1h_parse_type": r.rain_1h_parse_type,
            "temp_c": r.temp_c,
            "humidity_pct": r.humidity_pct,
            "wind_speed_ms": r.wind_speed_ms,
            "wind_dir_deg": r.wind_dir_deg,
            "precip_type_code": r.precip_type_code,
            "requested_at": r.requested_at,
            "raw_batch_time": r.raw_batch_time,
        }
        for r in std_dedup.values()
    ]

    if not std_rows:
        raise RuntimeError("No valid rows parsed from input CSV(s).")

    upsert_std_ultra_now(std_rows)
    district_rows = aggregate_ultra_now_by_district(std_rows, mappings)
    upsert_district_ultra_now(district_rows)

    print(
        f"[portal_ultra_now_representative_dong] loaded {len(std_rows)} std rows "
        f"({total_rows} parsed, {skipped} skipped); updated {len(district_rows)} district rows."
    )


if __name__ == "__main__":
    main()

