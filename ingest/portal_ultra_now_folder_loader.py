from __future__ import annotations

import argparse
import csv
import math
import re
import sys
import unicodedata
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.append(str(PROJECT_ROOT))

from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

from core.config import settings
from core.db import upsert_district_ultra_now, upsert_std_ultra_now
from core.district_agg import aggregate_ultra_now_by_district
from core.grid_map import DistrictGridMapping

KST = ZoneInfo("Asia/Seoul")

# 파일명 예:
#  삼성2동_뇌전_202001_202012.csv
#  강남구 2020년 초단기실황/삼성2동_강수_202001_202012.csv
FILE_VAR_RE = re.compile(
    r"^(?P<rep>[^_]+)_(?P<var>[^_]+)_(?P<start>\d{6})_(?P<end>\d{6})\.csv$",
    re.UNICODE,
)

# 헤더 예:
#  format: day,hour,value location:62_126 Start : 20250101
HEADER_RE = re.compile(
    r"location:(?P<nx>\d+)_(?P<ny>\d+).*?Start\s*:?[\s]*(?P<start>\d{8})",
    re.UNICODE,
)


def _decode_lines(path: Path):
    # 포털 CSV가 인코딩이 섞일 수 있어 폴백.
    for enc in ("utf-8-sig", "cp949", "euc-kr"):
        try:
            with path.open("r", encoding=enc, newline="") as fp:
                for line in fp:
                    yield line
            return
        except UnicodeDecodeError:
            continue
    # 마지막 시도 예외를 만들기 위해 다시 utf-8-sig로 열어본다.
    with path.open("r", encoding="utf-8-sig", newline=""):
        pass


def _parse_hour_hhmm(hour_str: str) -> tuple[int, int]:
    s = (hour_str or "").strip()
    if not s:
        raise ValueError("empty hour string")
    if not s.isdigit():
        s = re.sub(r"\D+", "", s)
    # 기대 포맷은 HHMM (예: 0000, 0100)
    s = s.zfill(4)
    hh = int(s[:2])
    mm = int(s[2:4])
    if hh > 23 or mm > 59:
        raise ValueError(f"invalid HHMM: {hour_str!r}")
    return hh, mm


def _to_int_like_string(value: float) -> str:
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return ""
    # PTY 코드가 0.000000 처럼 들어올 수 있어 int-like로 변환.
    rounded = int(round(value))
    return str(rounded)


@dataclass(frozen=True)
class VarFile:
    path: Path
    district_name: str
    var: str
    nx: int
    ny: int
    start_date: date


def _normalize_text(value: str) -> str:
    return unicodedata.normalize("NFC", value.strip())


def _district_name_from_path(path: Path) -> str:
    district_dir_name = _normalize_text(path.parent.name)
    match = re.match(r"^(?P<district>.+?)\s+\d{4}년", district_dir_name)
    if match:
        return _normalize_text(match.group("district"))
    return district_dir_name.split()[0]


def _map_var_to_std_column(var: str) -> str | None:
    # std.kma_ultra_now_std에 필요한 컬럼들만 매핑.
    # - 강수(강수량/강수): RN1 -> rain_1h_mm
    # - 기온: T1H -> temp_c
    # - 습도: REH -> humidity_pct
    # - 풍속: WSD -> wind_speed_ms
    # - 풍향: VEC -> wind_dir_deg
    # - 강수형태: PTY -> precip_type_code
    if var.startswith("강수") and var != "강수형태":
        return "rain"
    if var == "기온":
        return "temp"
    if var == "습도":
        return "humidity"
    if var == "풍속":
        return "wind_speed"
    if var == "풍향":
        return "wind_dir"
    if var == "강수형태":
        return "precip_type"
    return None


def _parse_var_file(path: Path) -> VarFile:
    m = FILE_VAR_RE.match(path.name)
    if not m:
        raise ValueError(f"Unexpected file name: {path.name}")

    # 첫 줄만 읽어서 nx/ny/start_date를 뽑는다.
    it = _decode_lines(path)
    first_line = next(it)
    header_m = HEADER_RE.search(first_line)
    if not header_m:
        raise ValueError(f"Could not parse header: {path} first_line={first_line!r}")

    nx = int(header_m.group("nx"))
    ny = int(header_m.group("ny"))
    start_date = datetime.strptime(header_m.group("start"), "%Y%m%d").date()

    return VarFile(
        path=path,
        district_name=_district_name_from_path(path),
        var=_normalize_text(m.group("var")),
        nx=nx,
        ny=ny,
        start_date=start_date,
    )


def _parse_values_to_rows(var_slot: str, var_path: Path, *, requested_at: datetime, raw_batch_time: datetime):
    """
    return: rows_by_dt[base_datetime] = partial_row_dict
    """
    rows_by_dt: dict[datetime, dict[str, Any]] = {}

    # 헤더 파싱을 위해 처음 1줄은 소비하고 나머지 day,hour,value만 파싱.
    it = _decode_lines(var_path)
    header_line = next(it)
    header_m = HEADER_RE.search(header_line)
    if not header_m:
        raise ValueError(f"Could not parse header: {var_path} first_line={header_line!r}")
    nx = int(header_m.group("nx"))
    ny = int(header_m.group("ny"))
    start_date = datetime.strptime(header_m.group("start"), "%Y%m%d").date()

    for line in it:
        line = line.strip()
        if not line:
            continue
        # 포털 파일은 day, hour, value 형태(중간에 공백 있을 수 있음)
        parts = [p.strip() for p in line.split(",")]
        if len(parts) < 3:
            continue
        day_str, hour_str, value_str = parts[0], parts[1], parts[2]
        if not day_str or not hour_str:
            continue
        try:
            day_idx = int(float(day_str))
        except ValueError:
            continue

        try:
            hh, mm = _parse_hour_hhmm(hour_str)
        except ValueError:
            continue

        base_dt = datetime.combine(start_date + timedelta(days=day_idx - 1), datetime.min.time()).replace(tzinfo=KST)
        base_dt = base_dt.replace(hour=hh, minute=mm)

        value = None
        v = value_str.strip()
        if v != "":
            try:
                value = float(v)
            except ValueError:
                value = None

        if var_slot == "rain":
            rain_val = value
            if rain_val is None:
                continue
            rows_by_dt[base_dt] = {
                "base_datetime": base_dt,
                "nx": nx,
                "ny": ny,
                "rain_1h_text": str(rain_val),
                "rain_1h_mm": float(rain_val),
                "rain_1h_parse_type": "exact",
                "temp_c": None,
                "humidity_pct": None,
                "wind_speed_ms": None,
                "wind_dir_deg": None,
                "precip_type_code": None,
                "requested_at": requested_at,
                "raw_batch_time": raw_batch_time,
            }
        elif var_slot == "temp":
            if base_dt not in rows_by_dt:
                rows_by_dt[base_dt] = {
                    "base_datetime": base_dt,
                    "nx": nx,
                    "ny": ny,
                    "rain_1h_text": None,
                    "rain_1h_mm": None,
                    "rain_1h_parse_type": None,
                    "temp_c": None,
                    "humidity_pct": None,
                    "wind_speed_ms": None,
                    "wind_dir_deg": None,
                    "precip_type_code": None,
                    "requested_at": requested_at,
                    "raw_batch_time": raw_batch_time,
                }
            rows_by_dt[base_dt]["temp_c"] = None if value is None else float(value)
        elif var_slot == "humidity":
            if base_dt not in rows_by_dt:
                rows_by_dt[base_dt] = {
                    "base_datetime": base_dt,
                    "nx": nx,
                    "ny": ny,
                    "rain_1h_text": None,
                    "rain_1h_mm": None,
                    "rain_1h_parse_type": None,
                    "temp_c": None,
                    "humidity_pct": None,
                    "wind_speed_ms": None,
                    "wind_dir_deg": None,
                    "precip_type_code": None,
                    "requested_at": requested_at,
                    "raw_batch_time": raw_batch_time,
                }
            rows_by_dt[base_dt]["humidity_pct"] = None if value is None else float(value)
        elif var_slot == "wind_speed":
            if base_dt not in rows_by_dt:
                rows_by_dt[base_dt] = {
                    "base_datetime": base_dt,
                    "nx": nx,
                    "ny": ny,
                    "rain_1h_text": None,
                    "rain_1h_mm": None,
                    "rain_1h_parse_type": None,
                    "temp_c": None,
                    "humidity_pct": None,
                    "wind_speed_ms": None,
                    "wind_dir_deg": None,
                    "precip_type_code": None,
                    "requested_at": requested_at,
                    "raw_batch_time": raw_batch_time,
                }
            rows_by_dt[base_dt]["wind_speed_ms"] = None if value is None else float(value)
        elif var_slot == "wind_dir":
            if base_dt not in rows_by_dt:
                rows_by_dt[base_dt] = {
                    "base_datetime": base_dt,
                    "nx": nx,
                    "ny": ny,
                    "rain_1h_text": None,
                    "rain_1h_mm": None,
                    "rain_1h_parse_type": None,
                    "temp_c": None,
                    "humidity_pct": None,
                    "wind_speed_ms": None,
                    "wind_dir_deg": None,
                    "precip_type_code": None,
                    "requested_at": requested_at,
                    "raw_batch_time": raw_batch_time,
                }
            rows_by_dt[base_dt]["wind_dir_deg"] = None if value is None else float(value)
        elif var_slot == "precip_type":
            if base_dt not in rows_by_dt:
                rows_by_dt[base_dt] = {
                    "base_datetime": base_dt,
                    "nx": nx,
                    "ny": ny,
                    "rain_1h_text": None,
                    "rain_1h_mm": None,
                    "rain_1h_parse_type": None,
                    "temp_c": None,
                    "humidity_pct": None,
                    "wind_speed_ms": None,
                    "wind_dir_deg": None,
                    "precip_type_code": None,
                    "requested_at": requested_at,
                    "raw_batch_time": raw_batch_time,
                }
            if value is None:
                code_str = None
            else:
                code_str = _to_int_like_string(value)
            rows_by_dt[base_dt]["precip_type_code"] = code_str
        else:
            # Should not happen
            continue

    return rows_by_dt


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Backfill portal representative-dong ultra_now CSVs into std.kma_ultra_now_std."
    )
    parser.add_argument("--source-dir", type=Path, required=True, help="@서울 초단기실황 root directory.")
    parser.add_argument("--mapping-csv", type=Path, default=Path(settings.district_grid_mapping_path))
    parser.add_argument(
        "--requested-at",
        type=str,
        default="",
        help="Optional requested_at/raw_batch_time override (ISO or 'YYYY-MM-DD HH:MM'). Default: now(KST).",
    )
    args = parser.parse_args()

    if not args.source_dir.exists():
        raise FileNotFoundError(args.source_dir)

    requested_at = datetime.now(KST)
    if args.requested_at:
        requested_at_str = args.requested_at.strip()
        try:
            dt = datetime.fromisoformat(requested_at_str)
            requested_at = dt if dt.tzinfo else dt.replace(tzinfo=KST)
            requested_at = requested_at.astimezone(KST)
        except ValueError:
            requested_at = datetime.strptime(requested_at_str, "%Y-%m-%d %H:%M").replace(tzinfo=KST)

    raw_batch_time = requested_at

    # 1) 파일 수집: (nx,ny,year) 그룹별로 필요한 변수 파일을 모은다.
    groups: dict[tuple[str, int, int, int], dict[str, list[Path]]] = defaultdict(lambda: defaultdict(list))

    csv_paths = sorted(args.source_dir.rglob("*.csv"))
    if not csv_paths:
        raise RuntimeError(f"No csv files under {args.source_dir}")

    for p in csv_paths:
        try:
            parsed = _parse_var_file(p)
        except Exception:
            continue

        std_slot = _map_var_to_std_column(parsed.var)
        if not std_slot:
            continue

        group_key = (parsed.district_name, parsed.nx, parsed.ny, parsed.start_date.year)
        groups[group_key][std_slot].append(parsed.path)

    # 2) 그룹별 적재
    required_slots = ["rain", "temp", "humidity", "wind_speed", "wind_dir", "precip_type"]
    total_groups = len(groups)
    loaded_groups = 0

    for (district_name, nx, ny, year), var_files in sorted(groups.items()):
        missing = [s for s in required_slots if not var_files.get(s)]
        if missing:
            # null overwriting 방지: 필요한 변수가 하나라도 비면 스킵한다.
            print(f"[portal_ultra_now_folder_loader][skip] nx={nx} ny={ny} year={year} missing={missing}")
            continue

        # 같은 슬롯 파일이 여러 개면 순서대로 덮어쓴다.
        # 주의: partial은 "해당 슬롯만 채우고 나머지는 None"이므로,
        # base_dt가 이미 존재할 때는 target 컬럼만 병합(나머지 none으로 덮지 않기)한다.
        target_cols_by_slot: dict[str, list[str]] = {
            "rain": ["rain_1h_text", "rain_1h_mm", "rain_1h_parse_type"],
            "temp": ["temp_c"],
            "humidity": ["humidity_pct"],
            "wind_speed": ["wind_speed_ms"],
            "wind_dir": ["wind_dir_deg"],
            "precip_type": ["precip_type_code"],
        }

        rows_by_dt: dict[datetime, dict[str, Any]] = {}

        for slot in required_slots:
            target_cols = target_cols_by_slot[slot]
            for var_path in var_files[slot]:
                partial = _parse_values_to_rows(
                    slot, var_path, requested_at=requested_at, raw_batch_time=raw_batch_time
                )

                for base_dt, part_row in partial.items():
                    if base_dt not in rows_by_dt:
                        rows_by_dt[base_dt] = part_row
                        continue

                    for col in target_cols:
                        rows_by_dt[base_dt][col] = part_row.get(col)

        std_rows = list(rows_by_dt.values())

        # 안전장치: 필요한 기본 값이 없는 row가 있으면 스킵
        if not std_rows:
            print(f"[portal_ultra_now_folder_loader][skip] nx={nx} ny={ny} year={year} empty std_rows")
            continue

        required_non_null = {
            "rain": "rain_1h_mm",
            "temp": "temp_c",
            "humidity": "humidity_pct",
            "wind_speed": "wind_speed_ms",
            "wind_dir": "wind_dir_deg",
            # precip_type_code는 0이 있을 수 있으니 None만 체크
            "precip_type": "precip_type_code",
        }
        if any(row.get(col) is None for row in std_rows for col in required_non_null.values()):
            print(f"[portal_ultra_now_folder_loader][skip] nx={nx} ny={ny} year={year} has null required columns")
            continue

        upsert_std_ultra_now(std_rows)
        district_rows = aggregate_ultra_now_by_district(
            std_rows,
            [DistrictGridMapping(district_name=district_name, nx=nx, ny=ny, weight=1.0)],
        )
        upsert_district_ultra_now(district_rows)

        loaded_groups += 1
        print(
            f"[portal_ultra_now_folder_loader][loaded] nx={nx} ny={ny} year={year} "
            f"std_rows={len(std_rows)} district_rows={len(district_rows)}"
        )

    print(
        f"[portal_ultra_now_folder_loader] groups={total_groups} loaded={loaded_groups} "
        f"source_dir={args.source_dir}"
    )


if __name__ == "__main__":
    main()

