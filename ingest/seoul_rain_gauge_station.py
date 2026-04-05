from __future__ import annotations

import argparse
import hashlib
import json
import sys
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.append(str(PROJECT_ROOT))

from openpyxl import load_workbook
from psycopg2.extras import Json, execute_batch

from core.config import settings
from core.db import get_conn


KST = ZoneInfo("Asia/Seoul")
DEFAULT_SOURCE_PATH = settings.project_root / "서울시 강우량계 위치데이터.xlsx"


@dataclass(frozen=True)
class RainGaugeRecord:
    source_file_name: str
    excel_row_number: int
    station_code: int
    effective_start_date: date | None
    effective_end_date: date | None
    station_name: str
    station_address: str | None
    managing_office: str | None
    latitude: float
    longitude: float
    site_altitude_m: float | None
    barometer_height_m: float | None
    thermometer_height_m: float | None
    anemometer_height_m: float | None
    raingauge_height_m: float | None
    is_current: bool
    source_row_hash: str
    row_json: dict[str, object | None]
    loaded_at: datetime


def _to_date(value: object) -> date | None:
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    if isinstance(value, str):
        return datetime.fromisoformat(value).date()
    raise ValueError(f"Unsupported date value: {value!r}")


def _to_float(value: object) -> float | None:
    if value is None or value == "":
        return None
    return float(value)


def _normalize_json_value(value: object) -> object | None:
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, date):
        return value.isoformat()
    return value


def _make_row_hash(row_json: dict[str, object | None]) -> str:
    payload = json.dumps(row_json, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def load_records(source_path: Path) -> list[RainGaugeRecord]:
    workbook = load_workbook(source_path, read_only=True, data_only=True)
    worksheet = workbook[workbook.sheetnames[0]]
    rows = worksheet.iter_rows(values_only=True)

    header: tuple[object, ...] | None = None
    records: list[RainGaugeRecord] = []
    loaded_at = datetime.now(KST)

    for row_number, row in enumerate(rows, start=1):
        if row_number == 2:
            header = row
            continue
        if row_number < 4 or header is None:
            continue
        if not any(value is not None and value != "" for value in row):
            continue

        row_map = {
            str(column): _normalize_json_value(value)
            for column, value in zip(header, row)
            if column is not None
        }
        station_code_raw = row_map.get("지점")
        station_name_raw = row_map.get("지점명")
        latitude_raw = row_map.get("위도")
        longitude_raw = row_map.get("경도")

        if station_code_raw is None or station_name_raw in (None, ""):
            continue
        if latitude_raw in (None, "") or longitude_raw in (None, ""):
            continue

        record = RainGaugeRecord(
            source_file_name=source_path.name,
            excel_row_number=row_number,
            station_code=int(station_code_raw),
            effective_start_date=_to_date(row_map.get("시작일")),
            effective_end_date=_to_date(row_map.get("종료일")),
            station_name=str(station_name_raw).strip(),
            station_address=(str(row_map["지점주소"]).strip() if row_map.get("지점주소") else None),
            managing_office=(str(row_map["관리관서"]).strip() if row_map.get("관리관서") else None),
            latitude=float(latitude_raw),
            longitude=float(longitude_raw),
            site_altitude_m=_to_float(row_map.get("노장해발고도(m)")),
            barometer_height_m=_to_float(row_map.get("기압계(관측장비지상높이(m))")),
            thermometer_height_m=_to_float(row_map.get("기온계(관측장비지상높이(m))")),
            anemometer_height_m=_to_float(row_map.get("풍속계(관측장비지상높이(m))")),
            raingauge_height_m=_to_float(row_map.get("강우계(관측장비지상높이(m))")),
            is_current=row_map.get("종료일") is None,
            source_row_hash=_make_row_hash(row_map),
            row_json=row_map,
            loaded_at=loaded_at,
        )
        records.append(record)

    return records


def replace_records(records: list[RainGaugeRecord], source_file_name: str) -> None:
    raw_insert_sql = """
    INSERT INTO raw.seoul_rain_gauge_station_raw (
        source_file_name,
        excel_row_number,
        station_code,
        effective_start_date,
        effective_end_date,
        station_name,
        station_address,
        managing_office,
        latitude,
        longitude,
        site_altitude_m,
        barometer_height_m,
        thermometer_height_m,
        anemometer_height_m,
        raingauge_height_m,
        source_row_hash,
        row_json,
        loaded_at
    )
    VALUES (
        %(source_file_name)s,
        %(excel_row_number)s,
        %(station_code)s,
        %(effective_start_date)s,
        %(effective_end_date)s,
        %(station_name)s,
        %(station_address)s,
        %(managing_office)s,
        %(latitude)s,
        %(longitude)s,
        %(site_altitude_m)s,
        %(barometer_height_m)s,
        %(thermometer_height_m)s,
        %(anemometer_height_m)s,
        %(raingauge_height_m)s,
        %(source_row_hash)s,
        %(row_json)s,
        %(loaded_at)s
    )
    """

    ref_insert_sql = """
    INSERT INTO ref.seoul_rain_gauge_station_history (
        station_code,
        effective_start_date,
        effective_end_date,
        station_name,
        station_address,
        managing_office,
        latitude,
        longitude,
        site_altitude_m,
        barometer_height_m,
        thermometer_height_m,
        anemometer_height_m,
        raingauge_height_m,
        geom,
        is_current,
        source_file_name,
        excel_row_number,
        source_row_hash,
        loaded_at,
        created_at,
        updated_at
    )
    VALUES (
        %(station_code)s,
        %(effective_start_date)s,
        %(effective_end_date)s,
        %(station_name)s,
        %(station_address)s,
        %(managing_office)s,
        %(latitude)s,
        %(longitude)s,
        %(site_altitude_m)s,
        %(barometer_height_m)s,
        %(thermometer_height_m)s,
        %(anemometer_height_m)s,
        %(raingauge_height_m)s,
        ST_SetSRID(ST_MakePoint(%(longitude)s, %(latitude)s), 4326),
        %(is_current)s,
        %(source_file_name)s,
        %(excel_row_number)s,
        %(source_row_hash)s,
        %(loaded_at)s,
        %(loaded_at)s,
        %(loaded_at)s
    )
    """

    prepared_rows = [
        {
            "source_file_name": record.source_file_name,
            "excel_row_number": record.excel_row_number,
            "station_code": record.station_code,
            "effective_start_date": record.effective_start_date,
            "effective_end_date": record.effective_end_date,
            "station_name": record.station_name,
            "station_address": record.station_address,
            "managing_office": record.managing_office,
            "latitude": record.latitude,
            "longitude": record.longitude,
            "site_altitude_m": record.site_altitude_m,
            "barometer_height_m": record.barometer_height_m,
            "thermometer_height_m": record.thermometer_height_m,
            "anemometer_height_m": record.anemometer_height_m,
            "raingauge_height_m": record.raingauge_height_m,
            "is_current": record.is_current,
            "source_row_hash": record.source_row_hash,
            "row_json": Json(record.row_json),
            "loaded_at": record.loaded_at,
        }
        for record in records
    ]

    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM raw.seoul_rain_gauge_station_raw WHERE source_file_name = %s",
                (source_file_name,),
            )
            cur.execute(
                "DELETE FROM ref.seoul_rain_gauge_station_history WHERE source_file_name = %s",
                (source_file_name,),
            )
            execute_batch(cur, raw_insert_sql, prepared_rows, page_size=settings.db_batch_size)
            execute_batch(cur, ref_insert_sql, prepared_rows, page_size=settings.db_batch_size)
        conn.commit()


def main() -> None:
    parser = argparse.ArgumentParser(description="Load Seoul rain gauge station history into PostGIS.")
    parser.add_argument(
        "--source",
        type=Path,
        default=DEFAULT_SOURCE_PATH,
        help="Path to the Excel workbook.",
    )
    args = parser.parse_args()

    source_path = args.source.resolve()
    if not source_path.exists():
        raise FileNotFoundError(f"Source file not found: {source_path}")

    records = load_records(source_path)
    if not records:
        raise RuntimeError(f"No valid rows found in: {source_path}")

    replace_records(records, source_path.name)

    current_count = sum(1 for record in records if record.is_current)
    print(
        f"loaded {len(records)} rain gauge history rows "
        f"({current_count} current rows) from {source_path.name}"
    )


if __name__ == "__main__":
    main()
