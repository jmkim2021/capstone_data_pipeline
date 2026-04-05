from __future__ import annotations

import argparse
import csv
import io
import sys
import unicodedata
from dataclasses import dataclass
from datetime import datetime
from itertools import islice
from pathlib import Path
from zipfile import ZipFile

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.append(str(PROJECT_ROOT))

from psycopg2.extras import Json, execute_values

from core.config import settings
from core.db import get_conn


DEFAULT_SOURCE_DIR_NAME = "서울시 방재기상관측(AWS) 지역구별 데이터"


@dataclass(frozen=True)
class AwsDistrictRow:
    district_name: str
    station_code: int
    observed_at: datetime
    temp_c: float | None
    wind_dir_deg: float | None
    wind_speed_ms: float | None
    precip_mm: float | None
    local_pressure_hpa: float | None
    sea_level_pressure_hpa: float | None
    humidity_pct: float | None
    solar_radiation_mj_m2: float | None
    sunshine_hr: float | None
    source_zip_name: str
    source_csv_name: str
    source_row_number: int
    row_json: dict[str, str | None]
    loaded_at: datetime


def _parse_float(value: str | None) -> float | None:
    if value is None:
        return None
    value = value.strip()
    if value == "":
        return None
    return float(value)


def _parse_dt(value: str) -> datetime:
    return datetime.strptime(value.strip(), "%Y-%m-%d %H:%M")


def _district_name_from_dir(dir_name: str) -> str:
    return unicodedata.normalize("NFC", dir_name.split(",")[0].strip())


def _resolve_default_source_dir() -> Path:
    direct_path = settings.project_root / DEFAULT_SOURCE_DIR_NAME
    if direct_path.exists():
        return direct_path

    target_name = unicodedata.normalize("NFC", DEFAULT_SOURCE_DIR_NAME)
    for child in settings.project_root.iterdir():
        normalized_name = unicodedata.normalize("NFC", child.name)
        if target_name == normalized_name and child.is_dir():
            return child
        if "방재기상관측" in normalized_name and "AWS" in normalized_name and child.is_dir():
            return child

    return direct_path


def iter_rows(source_dir: Path):
    districts_seen: set[str] = set()

    for district_dir in sorted(path for path in source_dir.iterdir() if path.is_dir()):
        district_name = _district_name_from_dir(district_dir.name)
        districts_seen.add(district_name)

        for zip_path in sorted(district_dir.glob("*.zip")):
            with ZipFile(zip_path) as zf:
                for member in zf.namelist():
                    if not member.lower().endswith(".csv"):
                        continue

                    with zf.open(member) as fp:
                        text_stream = io.TextIOWrapper(fp, encoding="cp949")
                        reader = csv.DictReader(text_stream)
                        loaded_at = datetime.now()

                        for row_number, row in enumerate(reader, start=2):
                            normalized = {str(k): (v.strip() if isinstance(v, str) else v) for k, v in row.items()}
                            station_code = int(float(normalized["지점"]))
                            yield AwsDistrictRow(
                                district_name=district_name,
                                station_code=station_code,
                                observed_at=_parse_dt(normalized["일시"]),
                                temp_c=_parse_float(normalized.get("기온(°C)")),
                                wind_dir_deg=_parse_float(normalized.get("풍향(deg)")),
                                wind_speed_ms=_parse_float(normalized.get("풍속(m/s)")),
                                precip_mm=_parse_float(normalized.get("강수량(mm)")),
                                local_pressure_hpa=_parse_float(normalized.get("현지기압(hPa)")),
                                sea_level_pressure_hpa=_parse_float(normalized.get("해면기압(hPa)")),
                                humidity_pct=_parse_float(normalized.get("습도(%)")),
                                solar_radiation_mj_m2=_parse_float(normalized.get("일사(MJ/m^2)")),
                                sunshine_hr=_parse_float(normalized.get("일조(hr)")),
                                source_zip_name=zip_path.name,
                                source_csv_name=Path(member).name,
                                source_row_number=row_number,
                                row_json=normalized,
                                loaded_at=loaded_at,
                            )


def _chunked(iterator, size: int):
    while True:
        chunk = list(islice(iterator, size))
        if not chunk:
            return
        yield chunk


def replace_rows(rows_iter, chunk_size: int = 5000) -> int:
    raw_sql = """
    INSERT INTO raw.seoul_aws_district_raw (
        district_name, station_code, observed_at, source_zip_name, source_csv_name,
        source_row_number, row_json, loaded_at
    )
    VALUES %s
    """

    std_sql = """
    INSERT INTO std.seoul_aws_district_hourly (
        district_name, station_code, observed_at, temp_c, wind_dir_deg, wind_speed_ms,
        precip_mm, local_pressure_hpa, sea_level_pressure_hpa, humidity_pct,
        solar_radiation_mj_m2, sunshine_hr, source_zip_name, source_csv_name,
        loaded_at
    )
    VALUES %s
    ON CONFLICT (district_name, observed_at)
    DO UPDATE SET
        station_code = EXCLUDED.station_code,
        temp_c = EXCLUDED.temp_c,
        wind_dir_deg = EXCLUDED.wind_dir_deg,
        wind_speed_ms = EXCLUDED.wind_speed_ms,
        precip_mm = EXCLUDED.precip_mm,
        local_pressure_hpa = EXCLUDED.local_pressure_hpa,
        sea_level_pressure_hpa = EXCLUDED.sea_level_pressure_hpa,
        humidity_pct = EXCLUDED.humidity_pct,
        solar_radiation_mj_m2 = EXCLUDED.solar_radiation_mj_m2,
        sunshine_hr = EXCLUDED.sunshine_hr,
        source_zip_name = EXCLUDED.source_zip_name,
        source_csv_name = EXCLUDED.source_csv_name,
        loaded_at = EXCLUDED.loaded_at
    """

    total_rows = 0
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("TRUNCATE TABLE raw.seoul_aws_district_raw")
            cur.execute("TRUNCATE TABLE std.seoul_aws_district_hourly")
            for chunk in _chunked(rows_iter, chunk_size):
                prepared_rows = [
                    (
                        row.district_name,
                        row.station_code,
                        row.observed_at,
                        row.temp_c,
                        row.wind_dir_deg,
                        row.wind_speed_ms,
                        row.precip_mm,
                        row.local_pressure_hpa,
                        row.sea_level_pressure_hpa,
                        row.humidity_pct,
                        row.solar_radiation_mj_m2,
                        row.sunshine_hr,
                        row.source_zip_name,
                        row.source_csv_name,
                        row.source_row_number,
                        Json(row.row_json),
                        row.loaded_at,
                    )
                    for row in chunk
                ]
                execute_values(
                    cur,
                    raw_sql,
                    [
                        (
                            r[0], r[1], r[2], r[12], r[13], r[14], r[15], r[16]
                        )
                        for r in prepared_rows
                    ],
                    page_size=chunk_size,
                )
                execute_values(
                    cur,
                    std_sql,
                    [
                        (
                            r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7],
                            r[8], r[9], r[10], r[11], r[12], r[13], r[16]
                        )
                        for r in prepared_rows
                    ],
                    page_size=chunk_size,
                )
                conn.commit()
                total_rows += len(prepared_rows)
    return total_rows


def main() -> None:
    parser = argparse.ArgumentParser(description="Load Seoul district AWS hourly data.")
    parser.add_argument("--source-dir", type=Path, default=_resolve_default_source_dir())
    args = parser.parse_args()

    source_dir = args.source_dir.resolve()
    if not source_dir.exists():
        raise FileNotFoundError(f"Source directory not found: {source_dir}")

    district_dirs = [path for path in source_dir.iterdir() if path.is_dir()]
    districts_seen = {_district_name_from_dir(path.name) for path in district_dirs}
    if not district_dirs:
        raise RuntimeError(f"No district directories found in {source_dir}")

    total_rows = replace_rows(iter_rows(source_dir))

    print(
        f"loaded {total_rows} AWS hourly rows "
        f"for {len(districts_seen)} districts "
        f"from {source_dir.name}"
    )


if __name__ == "__main__":
    main()
