from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from psycopg2.extras import Json, execute_batch

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.append(str(PROJECT_ROOT))

from core.config import settings
from core.db import get_conn


KST = ZoneInfo("Asia/Seoul")
DEFAULT_SOURCE_PATH = settings.project_root / "서울시 자연재해위험개선지구(침수지구) 현황.csv"
DEFAULT_ENCODING = "cp949"
SEOUL_DISTRICT_NAMES = [
    "종로구", "중구", "용산구", "성동구", "광진구", "동대문구", "중랑구",
    "성북구", "강북구", "도봉구", "노원구", "은평구", "서대문구", "마포구",
    "양천구", "강서구", "구로구", "금천구", "영등포구", "동작구", "관악구",
    "서초구", "강남구", "송파구", "강동구",
]


@dataclass(frozen=True)
class RiskZoneRecord:
    source_file_name: str
    source_encoding: str
    source_row_number: int
    serial_no: int | None
    zone_name: str
    risk_type: str | None
    location_text: str | None
    district_name: str | None
    facility_name: str | None
    facility_type: str | None
    designated_date: date | None
    designation_reason: str | None
    risk_factor: str | None
    progress_status: str | None
    managing_agency: str | None
    managing_contact: str | None
    source_row_hash: str
    row_json: dict[str, object | None]
    loaded_at: datetime


def _clean_text(value: object | None) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _to_int(value: object | None) -> int | None:
    text = _clean_text(value)
    if text is None:
        return None
    return int(text)


def _to_date(value: object | None) -> date | None:
    text = _clean_text(value)
    if text is None:
        return None
    return date.fromisoformat(text)


def _normalize_district_name(location_text: str | None, managing_agency: str | None) -> str | None:
    for candidate in [location_text, managing_agency]:
        if not candidate:
            continue
        for district_name in SEOUL_DISTRICT_NAMES:
            if district_name in candidate:
                return district_name
    return None


def _make_hash(row_json: dict[str, object | None]) -> str:
    payload = json.dumps(row_json, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def load_records(source_path: Path, encoding: str) -> list[RiskZoneRecord]:
    records: list[RiskZoneRecord] = []
    loaded_at = datetime.now(KST)

    with open(source_path, "r", encoding=encoding, newline="") as f:
        reader = csv.DictReader(f)
        for source_row_number, row in enumerate(reader, start=2):
            normalized_row = {key: _clean_text(value) for key, value in row.items()}
            zone_name = normalized_row.get("지구명")
            if not zone_name:
                continue

            location_text = normalized_row.get("위치")
            managing_agency = normalized_row.get("시설관리기관")
            district_name = _normalize_district_name(location_text, managing_agency)

            record = RiskZoneRecord(
                source_file_name=source_path.name,
                source_encoding=encoding,
                source_row_number=source_row_number,
                serial_no=_to_int(normalized_row.get("연번")),
                zone_name=zone_name,
                risk_type=normalized_row.get("유형"),
                location_text=location_text,
                district_name=district_name,
                facility_name=normalized_row.get("시설명"),
                facility_type=normalized_row.get("시설물유형"),
                designated_date=_to_date(normalized_row.get("지정일자")),
                designation_reason=normalized_row.get("지정사유"),
                risk_factor=normalized_row.get("위험요인"),
                progress_status=normalized_row.get("추진사항"),
                managing_agency=managing_agency,
                managing_contact=normalized_row.get("시설관리연락처"),
                source_row_hash=_make_hash(normalized_row),
                row_json=normalized_row,
                loaded_at=loaded_at,
            )
            records.append(record)

    return records


def replace_records(records: list[RiskZoneRecord], source_file_name: str) -> None:
    raw_insert_sql = """
    INSERT INTO raw.seoul_disaster_risk_zone_raw (
        source_file_name,
        source_encoding,
        source_row_number,
        source_serial_no,
        row_json,
        loaded_at
    )
    VALUES (
        %(source_file_name)s,
        %(source_encoding)s,
        %(source_row_number)s,
        %(serial_no)s,
        %(row_json)s,
        %(loaded_at)s
    )
    """

    ref_insert_sql = """
    INSERT INTO ref.seoul_disaster_risk_zone (
        source_file_name,
        source_encoding,
        source_row_number,
        serial_no,
        zone_name,
        risk_type,
        location_text,
        district_name,
        facility_name,
        facility_type,
        designated_date,
        designation_reason,
        risk_factor,
        progress_status,
        managing_agency,
        managing_contact,
        has_geometry,
        geom,
        source_row_hash,
        row_json,
        loaded_at,
        created_at,
        updated_at
    )
    VALUES (
        %(source_file_name)s,
        %(source_encoding)s,
        %(source_row_number)s,
        %(serial_no)s,
        %(zone_name)s,
        %(risk_type)s,
        %(location_text)s,
        %(district_name)s,
        %(facility_name)s,
        %(facility_type)s,
        %(designated_date)s,
        %(designation_reason)s,
        %(risk_factor)s,
        %(progress_status)s,
        %(managing_agency)s,
        %(managing_contact)s,
        FALSE,
        NULL,
        %(source_row_hash)s,
        %(row_json)s,
        %(loaded_at)s,
        %(loaded_at)s,
        %(loaded_at)s
    )
    """

    prepared_rows = [
        {
            "source_file_name": record.source_file_name,
            "source_encoding": record.source_encoding,
            "source_row_number": record.source_row_number,
            "serial_no": record.serial_no,
            "zone_name": record.zone_name,
            "risk_type": record.risk_type,
            "location_text": record.location_text,
            "district_name": record.district_name,
            "facility_name": record.facility_name,
            "facility_type": record.facility_type,
            "designated_date": record.designated_date,
            "designation_reason": record.designation_reason,
            "risk_factor": record.risk_factor,
            "progress_status": record.progress_status,
            "managing_agency": record.managing_agency,
            "managing_contact": record.managing_contact,
            "source_row_hash": record.source_row_hash,
            "row_json": Json(record.row_json),
            "loaded_at": record.loaded_at,
        }
        for record in records
    ]

    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM raw.seoul_disaster_risk_zone_raw WHERE source_file_name = %s",
                (source_file_name,),
            )
            cur.execute(
                "DELETE FROM ref.seoul_disaster_risk_zone WHERE source_file_name = %s",
                (source_file_name,),
            )
            execute_batch(cur, raw_insert_sql, prepared_rows, page_size=settings.db_batch_size)
            execute_batch(cur, ref_insert_sql, prepared_rows, page_size=settings.db_batch_size)
        conn.commit()


def main() -> None:
    parser = argparse.ArgumentParser(description="Load Seoul disaster risk zone CSV.")
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE_PATH, help="Path to CSV file.")
    parser.add_argument("--encoding", default=DEFAULT_ENCODING, help="CSV encoding.")
    args = parser.parse_args()

    source_path = args.source.resolve()
    if not source_path.exists():
        raise FileNotFoundError(f"Source file not found: {source_path}")

    records = load_records(source_path, args.encoding)
    if not records:
        raise RuntimeError(f"No valid rows found in: {source_path}")

    replace_records(records, source_path.name)
    print(f"loaded {len(records)} disaster risk zone rows from {source_path.name}")


if __name__ == "__main__":
    main()
