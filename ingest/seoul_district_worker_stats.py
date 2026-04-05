from __future__ import annotations

import argparse
import csv
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from psycopg2.extras import execute_batch

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.append(str(PROJECT_ROOT))

from core.config import settings
from core.db import get_conn


KST = ZoneInfo("Asia/Seoul")
DEFAULT_ENCODING = "utf-8-sig"
DEFAULT_SOURCE_PATH = settings.project_root / "사업체현황+종사자수(산업대분류별_성별_동별)_20260403163145.csv"
SEOUL_DISTRICT_NAMES = [
    "종로구", "중구", "용산구", "성동구", "광진구", "동대문구", "중랑구",
    "성북구", "강북구", "도봉구", "노원구", "은평구", "서대문구", "마포구",
    "양천구", "강서구", "구로구", "금천구", "영등포구", "동작구", "관악구",
    "서초구", "강남구", "송파구", "강동구",
]
DISTRICT_NAME_SET = set(SEOUL_DISTRICT_NAMES)


@dataclass(frozen=True)
class WorkerStatRecord:
    base_year: int
    district_name: str
    total_worker_count: int
    source_file_name: str
    loaded_at: datetime


def _clean_text(value: object | None) -> str | None:
    if value is None:
        return None
    text = str(value).strip().strip('"')
    return text or None


def _normalize_district_name(value: object | None) -> str | None:
    text = _clean_text(value)
    if text is None:
        return None

    normalized = text.replace(" ", "")
    if normalized.endswith("특별시"):
        normalized = normalized[:-4]
    if normalized.startswith("서울시"):
        normalized = normalized[3:]
    if normalized.startswith("서울특별시"):
        normalized = normalized[5:]

    return normalized if normalized in DISTRICT_NAME_SET else None


def _parse_int(value: object | None) -> int | None:
    text = _clean_text(value)
    if text is None or text == "-":
        return None
    return int(text.replace(",", ""))


def _resolve_required_columns(header_rows: list[list[str]]) -> tuple[int, int, int, int]:
    if len(header_rows) < 3:
        raise ValueError("CSV header must contain at least 3 rows.")

    year_row, category_row, metric_row = header_rows[:3]

    district_level1_idx: int | None = None
    district_name_idx: int | None = None
    total_worker_idx: int | None = None

    for idx, year_value in enumerate(year_row):
        category_value = category_row[idx] if idx < len(category_row) else ""
        metric_value = metric_row[idx] if idx < len(metric_row) else ""

        if category_value == "동별(1)":
            district_level1_idx = idx
        elif category_value == "동별(2)":
            district_name_idx = idx
        elif (
            _clean_text(year_value) == "2024"
            and _clean_text(category_value) == "합계"
            and _clean_text(metric_value) == "총종사자수"
        ):
            total_worker_idx = idx

    if district_level1_idx is None or district_name_idx is None or total_worker_idx is None:
        raise ValueError("Failed to resolve required columns from CSV header.")

    base_year = _parse_int(year_row[total_worker_idx])
    if base_year is None:
        raise ValueError("Failed to parse base year from total worker column.")

    return district_level1_idx, district_name_idx, total_worker_idx, base_year


def load_records(source_path: Path, encoding: str) -> list[WorkerStatRecord]:
    loaded_at = datetime.now(KST)
    by_district: dict[str, WorkerStatRecord] = {}

    with open(source_path, "r", encoding=encoding, newline="") as f:
        reader = csv.reader(f)
        header_rows = [next(reader) for _ in range(3)]
        district_level1_idx, district_name_idx, total_worker_idx, base_year = _resolve_required_columns(header_rows)

        for source_row_number, row in enumerate(reader, start=4):
            district_level1 = _clean_text(row[district_level1_idx]) if district_level1_idx < len(row) else None
            district_name = _normalize_district_name(row[district_name_idx] if district_name_idx < len(row) else None)

            # 동별(1)=합계, 동별(2)=서울 25개 자치구만 운영 적재 대상으로 남긴다.
            if district_level1 != "합계" or district_name is None:
                continue

            total_worker_count = _parse_int(row[total_worker_idx] if total_worker_idx < len(row) else None)
            if total_worker_count is None:
                raise ValueError(
                    f"Missing total_worker_count for district={district_name} at source_row={source_row_number}"
                )
            if total_worker_count < 0:
                raise ValueError(
                    f"Negative total_worker_count for district={district_name} at source_row={source_row_number}"
                )
            if district_name in by_district:
                raise ValueError(f"Duplicate district row detected for district={district_name}")

            by_district[district_name] = WorkerStatRecord(
                base_year=base_year,
                district_name=district_name,
                total_worker_count=total_worker_count,
                source_file_name=source_path.name,
                loaded_at=loaded_at,
            )

    missing_districts = [name for name in SEOUL_DISTRICT_NAMES if name not in by_district]
    if missing_districts:
        raise RuntimeError(f"Missing district rows: {', '.join(missing_districts)}")

    return [by_district[name] for name in SEOUL_DISTRICT_NAMES]


def replace_records(records: list[WorkerStatRecord]) -> None:
    if not records:
        raise ValueError("No records to load.")

    base_year = records[0].base_year
    insert_sql = """
    INSERT INTO ref.seoul_district_worker_stats (
        base_year,
        district_name,
        total_worker_count,
        source_file_name,
        loaded_at
    )
    VALUES (
        %(base_year)s,
        %(district_name)s,
        %(total_worker_count)s,
        %(source_file_name)s,
        %(loaded_at)s
    )
    ON CONFLICT (base_year, district_name)
    DO UPDATE SET
        total_worker_count = EXCLUDED.total_worker_count,
        source_file_name = EXCLUDED.source_file_name,
        loaded_at = EXCLUDED.loaded_at
    """

    prepared_rows = [
        {
            "base_year": record.base_year,
            "district_name": record.district_name,
            "total_worker_count": record.total_worker_count,
            "source_file_name": record.source_file_name,
            "loaded_at": record.loaded_at,
        }
        for record in records
    ]

    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM ref.seoul_district_worker_stats WHERE base_year = %s", (base_year,))
            execute_batch(cur, insert_sql, prepared_rows, page_size=settings.db_batch_size)
        conn.commit()


def validate_loaded_rows(base_year: int) -> dict[str, int]:
    validation_sql = """
    SELECT
        COUNT(*) AS row_count,
        COUNT(DISTINCT district_name) AS district_count,
        COUNT(*) FILTER (WHERE total_worker_count IS NULL) AS null_worker_count_rows,
        COUNT(*) FILTER (WHERE total_worker_count < 0) AS negative_worker_count_rows
    FROM ref.seoul_district_worker_stats
    WHERE base_year = %s
    """

    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(validation_sql, (base_year,))
            row_count, district_count, null_rows, negative_rows = cur.fetchone()

    result = {
        "row_count": row_count,
        "district_count": district_count,
        "null_worker_count_rows": null_rows,
        "negative_worker_count_rows": negative_rows,
    }

    if row_count != 25:
        raise RuntimeError(f"Validation failed: row_count={row_count}, expected=25")
    if district_count != 25:
        raise RuntimeError(f"Validation failed: district_count={district_count}, expected=25")
    if null_rows != 0:
        raise RuntimeError(f"Validation failed: null total_worker_count rows={null_rows}")
    if negative_rows != 0:
        raise RuntimeError(f"Validation failed: negative total_worker_count rows={negative_rows}")

    return result


def main() -> None:
    parser = argparse.ArgumentParser(description="Load Seoul district total worker counts from CSV.")
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE_PATH, help="Path to CSV file.")
    parser.add_argument("--encoding", default=DEFAULT_ENCODING, help="CSV encoding.")
    args = parser.parse_args()

    source_path = args.source.resolve()
    if not source_path.exists():
        raise FileNotFoundError(f"Source file not found: {source_path}")

    records = load_records(source_path, args.encoding)
    replace_records(records)
    validation_result = validate_loaded_rows(records[0].base_year)

    print(
        f"loaded {len(records)} district worker stats rows from {source_path.name} "
        f"(base_year={records[0].base_year}, validation={validation_result})"
    )


if __name__ == "__main__":
    main()
