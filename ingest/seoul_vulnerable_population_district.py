"""서울 자치구 단위 취약계층 밀집도 데이터 로더.

입력: 취약계층 밀집도 데이터.zip
  ├── 고령자현황_*.csv                  (4행 다중 헤더, 2025 Q4 기준)
  ├── 장애인+현황(장애유형별_동별)_*.csv  (4행 다중 헤더, 2024년 기준)
  ├── 국민기초생활보장+수급자(2020+이후)_*.csv (4행 다중 헤더, 2024년 기준)
  └── 자치구별_지하반지하주택_정리.csv    (단순 헤더, 수집일 2026-04-03)

출력: ref.seoul_vulnerable_population_district_snapshot (25행, PK=district_name)

비율(ratio) 저장 단위: 소수 (0.0~1.0).
  - elderly_population_ratio        = elderly_total / total_population  (동일 소스)
  - disabled_population_ratio       = disabled_total / total_population  (분모=고령자현황, 소스년도 상이)
  - basic_livelihood_recipient_ratio = recipient_total / total_population (분모=고령자현황, 소스년도 상이)
  - aged_basement_household_ratio   = 원본 % / 100
"""

from __future__ import annotations

import argparse
import csv
import io
import re
import sys
import unicodedata
import zipfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional
from zoneinfo import ZoneInfo

from psycopg2.extras import execute_batch

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.append(str(PROJECT_ROOT))

from core.config import settings
from core.db import get_conn

KST = ZoneInfo("Asia/Seoul")
DEFAULT_ENCODING = "utf-8-sig"
DEFAULT_ZIP_PATH = PROJECT_ROOT / "취약계층 밀집도 데이터.zip"

SEOUL_DISTRICT_NAMES = [
    "종로구", "중구", "용산구", "성동구", "광진구", "동대문구", "중랑구",
    "성북구", "강북구", "도봉구", "노원구", "은평구", "서대문구", "마포구",
    "양천구", "강서구", "구로구", "금천구", "영등포구", "동작구", "관악구",
    "서초구", "강남구", "송파구", "강동구",
]
DISTRICT_NAME_SET = set(SEOUL_DISTRICT_NAMES)
SKIP_NAMES = {"합계", "소계", "본청", "서울특별시", "서울시"}

# ---------------------------------------------------------------------------
# 공통 유틸
# ---------------------------------------------------------------------------

def _clean(value: object) -> str:
    """공백·따옴표 제거."""
    if value is None:
        return ""
    return str(value).strip().strip('"').strip()


def _normalize_district_name(value: object) -> Optional[str]:
    text = _clean(value)
    if not text:
        return None
    text = text.replace(" ", "")
    for prefix in ("서울특별시", "서울시"):
        if text.startswith(prefix):
            text = text[len(prefix):]
    return text if text in DISTRICT_NAME_SET else None


def _parse_int(value: object) -> Optional[int]:
    text = _clean(value)
    if not text or text == "-":
        return None
    try:
        return int(text.replace(",", ""))
    except ValueError:
        return None


def _parse_float(value: object) -> Optional[float]:
    text = _clean(value)
    if not text or text == "-":
        return None
    try:
        return float(text.replace(",", ""))
    except ValueError:
        return None


def _safe_ratio(numerator: Optional[int], denominator: Optional[int]) -> Optional[float]:
    if numerator is None or denominator is None or denominator == 0:
        return None
    return round(numerator / denominator, 8)


def _open_csv_from_bytes(data: bytes, encoding: str = DEFAULT_ENCODING) -> list[list[str]]:
    text = data.decode(encoding)
    reader = csv.reader(io.StringIO(text))
    return list(reader)


# ---------------------------------------------------------------------------
# ZIP 열기
# ---------------------------------------------------------------------------

def _extract_csv_from_zip(
    zip_path: Path,
) -> dict[str, bytes]:
    """ZIP에서 CSV(MACOSX 제외) 추출. key=NFC-정규화된 basename."""
    result: dict[str, bytes] = {}
    with zipfile.ZipFile(zip_path, "r") as z:
        for info in z.infolist():
            try:
                fname = info.filename.encode("cp437").decode("utf-8")
            except (UnicodeDecodeError, UnicodeEncodeError):
                fname = info.filename
            # macOS ZIP이 NFD 파일명을 생성하므로 NFC로 정규화
            fname = unicodedata.normalize("NFC", fname)
            if fname.startswith("__MACOSX"):
                continue
            if not fname.lower().endswith(".csv"):
                continue
            basename = Path(fname).name
            result[basename] = z.read(info.filename)
    return result


def _find_csv(
    csvs: dict[str, bytes],
    keyword: str,
) -> tuple[str, bytes]:
    """keyword가 파일명에 포함된 CSV를 반환. 없으면 KeyError."""
    matches = [k for k in csvs if keyword in k]
    if not matches:
        raise KeyError(f"ZIP에서 '{keyword}'를 포함한 CSV를 찾을 수 없음. 파일 목록: {list(csvs)}")
    if len(matches) > 1:
        raise KeyError(f"'{keyword}' 키워드 CSV가 여러 개 매칭됨: {matches}")
    name = matches[0]
    return name, csvs[name]


# ---------------------------------------------------------------------------
# A. 고령자현황 파서
# ---------------------------------------------------------------------------
# 구조: 4행 다중 헤더 + 데이터
#   row0: 동별(1), 동별(2), 2025 4/4, ...   ← year/quarter
#   row1: 동별(1), 동별(2), 전체인구, ..., 65세이상 인구, ...
#   row2: 동별(1), 동별(2), 소계, 남자, 여자, 소계, 남자, 여자, 내국인, ..., 등록외국인, ...
#   row3: 동별(1), 동별(2), 소계, 소계, 소계, 소계, 소계, 소계, 소계, 남자, 여자, 소계, 남자, 여자
#
# 타깃 인덱스 (row1/row2/row3 조합으로 동적 탐색):
#   total_population         : row1=전체인구,  row2=소계, row3=소계
#   elderly_total            : row1=65세이상 인구, row2=소계, row3=소계
#   elderly_korean_total     : row1=65세이상 인구, row2=내국인, row3=소계
#   elderly_foreign_total    : row1=65세이상 인구, row2=등록외국인, row3=소계
#
# 데이터 행 조건: 동별(1)=합계, 동별(2)=25개 자치구 중 하나

@dataclass(frozen=True)
class ElderlyRecord:
    district_name: str
    total_population: Optional[int]
    elderly_population_total: Optional[int]
    elderly_population_korean_total: Optional[int]
    elderly_population_foreign_total: Optional[int]
    source_label: str
    source_year: int


def _resolve_elderly_columns(
    headers: list[list[str]],
) -> tuple[int, int, int, int, int, str, int]:
    """
    Returns:
        district_col, total_pop_col, elderly_total_col,
        elderly_korean_col, elderly_foreign_col,
        source_label, source_year
    """
    if len(headers) < 4:
        raise ValueError(f"고령자현황: 헤더 행이 4행 미만 ({len(headers)}행)")
    h0, h1, h2, h3 = headers[0], headers[1], headers[2], headers[3]

    # 소스 시점: h0 중 "2025 4/4" 형태 값의 첫 번째
    source_label = ""
    source_year = 0
    for val in h0:
        v = _clean(val)
        if re.match(r"\d{4}", v):
            source_label = v
            m = re.match(r"(\d{4})", v)
            if m:
                source_year = int(m.group(1))
            break
    if not source_label:
        raise ValueError("고령자현황: 헤더 row0에서 연도 값을 찾을 수 없음")

    # district 열: h1='동별(2)'
    district_col: Optional[int] = None
    total_pop_col: Optional[int] = None
    elderly_total_col: Optional[int] = None
    elderly_korean_col: Optional[int] = None
    elderly_foreign_col: Optional[int] = None

    for idx in range(len(h0)):
        c1 = _clean(h1[idx]) if idx < len(h1) else ""
        c2 = _clean(h2[idx]) if idx < len(h2) else ""
        c3 = _clean(h3[idx]) if idx < len(h3) else ""

        if c1 == "동별(2)":
            district_col = idx
        elif c1 == "전체인구" and c2 == "소계" and c3 == "소계":
            total_pop_col = idx
        elif c1 == "65세이상 인구" and c2 == "소계" and c3 == "소계":
            elderly_total_col = idx
        elif c1 == "65세이상 인구" and c2 == "내국인" and c3 == "소계":
            elderly_korean_col = idx
        elif c1 == "65세이상 인구" and c2 == "등록외국인" and c3 == "소계":
            elderly_foreign_col = idx

    missing = []
    if district_col is None:
        missing.append("district_col(동별(2))")
    if total_pop_col is None:
        missing.append("total_pop_col(전체인구/소계/소계)")
    if elderly_total_col is None:
        missing.append("elderly_total_col(65세이상/소계/소계)")
    if missing:
        raise ValueError(f"고령자현황: 필수 컬럼을 찾을 수 없음: {missing}")

    return (
        district_col, total_pop_col, elderly_total_col,
        elderly_korean_col, elderly_foreign_col,
        source_label, source_year,
    )


def parse_elderly_csv(data: bytes, encoding: str = DEFAULT_ENCODING) -> list[ElderlyRecord]:
    rows = _open_csv_from_bytes(data, encoding)
    if len(rows) < 5:
        raise ValueError(f"고령자현황: 행 수 부족 ({len(rows)})")

    headers = rows[:4]
    (
        district_col, total_pop_col, elderly_total_col,
        elderly_korean_col, elderly_foreign_col,
        source_label, source_year,
    ) = _resolve_elderly_columns(headers)

    by_district: dict[str, ElderlyRecord] = {}
    for row_num, row in enumerate(rows[4:], start=5):
        if len(row) <= max(district_col, total_pop_col, elderly_total_col):
            continue
        level1 = _clean(row[0])
        district_name = _normalize_district_name(row[district_col])
        if level1 != "합계" or district_name is None:
            continue

        if district_name in by_district:
            raise ValueError(f"고령자현황: 중복 자치구 행 (district={district_name}, row={row_num})")

        by_district[district_name] = ElderlyRecord(
            district_name=district_name,
            total_population=_parse_int(row[total_pop_col]),
            elderly_population_total=_parse_int(row[elderly_total_col]),
            elderly_population_korean_total=(
                _parse_int(row[elderly_korean_col])
                if elderly_korean_col is not None and elderly_korean_col < len(row)
                else None
            ),
            elderly_population_foreign_total=(
                _parse_int(row[elderly_foreign_col])
                if elderly_foreign_col is not None and elderly_foreign_col < len(row)
                else None
            ),
            source_label=source_label,
            source_year=source_year,
        )

    missing = [n for n in SEOUL_DISTRICT_NAMES if n not in by_district]
    if missing:
        raise RuntimeError(f"고령자현황: 누락 자치구: {missing}")
    return [by_district[n] for n in SEOUL_DISTRICT_NAMES]


# ---------------------------------------------------------------------------
# B. 장애인 현황 파서
# ---------------------------------------------------------------------------
# 구조: 4행 다중 헤더 + 데이터
#   row0: 동별(1), 동별(2), 2024, 2024, ...
#   row1: 동별(1), 동별(2), 합계, 합계, ...
#   row2: 동별(1), 동별(2), 소계, 소계, 소계, 지체, ...
#   row3: 동별(1), 동별(2), 계, 남자, 여자, ...
#
# 타깃:
#   disabled_total  : row1=합계, row2=소계, row3=계
#   disabled_male   : row1=합계, row2=소계, row3=남자
#   disabled_female : row1=합계, row2=소계, row3=여자
#
# 데이터 행 조건: 동별(1)=합계, 동별(2)=25개 자치구 중 하나

@dataclass(frozen=True)
class DisabledRecord:
    district_name: str
    disabled_population_total: Optional[int]
    disabled_population_male: Optional[int]
    disabled_population_female: Optional[int]
    source_year: int


def _resolve_disabled_columns(
    headers: list[list[str]],
) -> tuple[int, int, int, int, int]:
    """
    Returns: district_col, total_col, male_col, female_col, source_year
    """
    if len(headers) < 4:
        raise ValueError(f"장애인현황: 헤더 행이 4행 미만 ({len(headers)}행)")
    h0, h1, h2, h3 = headers[0], headers[1], headers[2], headers[3]

    source_year = 0
    for val in h0:
        v = _clean(val)
        if re.match(r"^\d{4}$", v):
            source_year = int(v)
            break
    if not source_year:
        raise ValueError("장애인현황: 헤더 row0에서 연도 값을 찾을 수 없음")

    district_col: Optional[int] = None
    total_col: Optional[int] = None
    male_col: Optional[int] = None
    female_col: Optional[int] = None

    for idx in range(len(h0)):
        c1 = _clean(h1[idx]) if idx < len(h1) else ""
        c2 = _clean(h2[idx]) if idx < len(h2) else ""
        c3 = _clean(h3[idx]) if idx < len(h3) else ""

        if c2 == "동별(2)":
            district_col = idx
        elif c1 == "합계" and c2 == "소계" and c3 == "계":
            total_col = idx
        elif c1 == "합계" and c2 == "소계" and c3 == "남자":
            male_col = idx
        elif c1 == "합계" and c2 == "소계" and c3 == "여자":
            female_col = idx

    # district_col fallback: h2='동별(2)' 못 찾으면 h1='동별(2)'
    if district_col is None:
        for idx in range(len(h1)):
            if _clean(h1[idx]) == "동별(2)":
                district_col = idx
                break

    missing = []
    if district_col is None:
        missing.append("district_col(동별(2))")
    if total_col is None:
        missing.append("total_col(합계/소계/계)")
    if missing:
        raise ValueError(f"장애인현황: 필수 컬럼 없음: {missing}")

    return district_col, total_col, male_col, female_col, source_year


def parse_disabled_csv(data: bytes, encoding: str = DEFAULT_ENCODING) -> list[DisabledRecord]:
    rows = _open_csv_from_bytes(data, encoding)
    if len(rows) < 5:
        raise ValueError(f"장애인현황: 행 수 부족 ({len(rows)})")

    headers = rows[:4]
    district_col, total_col, male_col, female_col, source_year = _resolve_disabled_columns(headers)

    by_district: dict[str, DisabledRecord] = {}
    for row_num, row in enumerate(rows[4:], start=5):
        if len(row) <= max(district_col, total_col):
            continue
        level1 = _clean(row[0])
        district_name = _normalize_district_name(row[district_col])
        if level1 != "합계" or district_name is None:
            continue

        if district_name in by_district:
            raise ValueError(f"장애인현황: 중복 자치구 행 (district={district_name}, row={row_num})")

        by_district[district_name] = DisabledRecord(
            district_name=district_name,
            disabled_population_total=_parse_int(row[total_col]),
            disabled_population_male=(
                _parse_int(row[male_col])
                if male_col is not None and male_col < len(row) else None
            ),
            disabled_population_female=(
                _parse_int(row[female_col])
                if female_col is not None and female_col < len(row) else None
            ),
            source_year=source_year,
        )

    missing = [n for n in SEOUL_DISTRICT_NAMES if n not in by_district]
    if missing:
        raise RuntimeError(f"장애인현황: 누락 자치구: {missing}")
    return [by_district[n] for n in SEOUL_DISTRICT_NAMES]


# ---------------------------------------------------------------------------
# C. 국민기초생활보장 수급자 파서
# ---------------------------------------------------------------------------
# 구조: 4행 다중 헤더 + 데이터
#   row0: 동별(1), 2024, ...               ← year
#   row1: 동별(1), 총 수급자, ...
#   row2: 동별(1), 가구 (가구), 시설수 (개소), 인원 (명), 인원 (명), 인원 (명), ...
#   row3: 동별(1), 소계, 소계, 소계, 남자, 여자, ...
#
# 타깃:
#   household_count    : row1=총 수급자, row2=가구 (가구), row3=소계
#   recipient_total    : row1=총 수급자, row2=인원 (명), row3=소계  (첫 번째 인원/소계)
#
# 데이터 행 조건: 동별(1)이 25개 자치구 중 하나 (합계/본청 제외)

@dataclass(frozen=True)
class BasicLivelihoodRecord:
    district_name: str
    basic_livelihood_recipient_total: Optional[int]
    basic_livelihood_household_count: Optional[int]
    source_year: int


def _resolve_basic_livelihood_columns(
    headers: list[list[str]],
) -> tuple[int, int, int]:
    """
    Returns: household_col, recipient_col, source_year
    (district는 항상 col 0)
    """
    if len(headers) < 4:
        raise ValueError(f"기초생보: 헤더 행이 4행 미만 ({len(headers)}행)")
    h0, h1, h2, h3 = headers[0], headers[1], headers[2], headers[3]

    source_year = 0
    for val in h0:
        v = _clean(val)
        if re.match(r"^\d{4}$", v):
            source_year = int(v)
            break
    if not source_year:
        raise ValueError("기초생보: 헤더 row0에서 연도 값을 찾을 수 없음")

    household_col: Optional[int] = None
    recipient_col: Optional[int] = None

    for idx in range(len(h0)):
        c1 = _clean(h1[idx]) if idx < len(h1) else ""
        c2 = _clean(h2[idx]) if idx < len(h2) else ""
        c3 = _clean(h3[idx]) if idx < len(h3) else ""

        # 총 수급자 / 가구 (가구) / 소계
        if c1 == "총 수급자" and "가구" in c2 and c3 == "소계":
            if household_col is None:
                household_col = idx
        # 총 수급자 / 인원 (명) / 소계 (첫 번째만 = 총합)
        elif c1 == "총 수급자" and "인원" in c2 and c3 == "소계":
            if recipient_col is None:
                recipient_col = idx

    missing = []
    if household_col is None:
        missing.append("household_col(총 수급자/가구/소계)")
    if recipient_col is None:
        missing.append("recipient_col(총 수급자/인원/소계)")
    if missing:
        raise ValueError(f"기초생보: 필수 컬럼 없음: {missing}")

    return household_col, recipient_col, source_year


def parse_basic_livelihood_csv(data: bytes, encoding: str = DEFAULT_ENCODING) -> list[BasicLivelihoodRecord]:
    rows = _open_csv_from_bytes(data, encoding)
    if len(rows) < 5:
        raise ValueError(f"기초생보: 행 수 부족 ({len(rows)})")

    headers = rows[:4]
    household_col, recipient_col, source_year = _resolve_basic_livelihood_columns(headers)

    by_district: dict[str, BasicLivelihoodRecord] = {}
    for row_num, row in enumerate(rows[4:], start=5):
        if len(row) <= max(household_col, recipient_col):
            continue
        district_name = _normalize_district_name(row[0])
        if district_name is None:
            continue

        if district_name in by_district:
            raise ValueError(f"기초생보: 중복 자치구 행 (district={district_name}, row={row_num})")

        by_district[district_name] = BasicLivelihoodRecord(
            district_name=district_name,
            basic_livelihood_recipient_total=_parse_int(row[recipient_col]),
            basic_livelihood_household_count=_parse_int(row[household_col]),
            source_year=source_year,
        )

    missing = [n for n in SEOUL_DISTRICT_NAMES if n not in by_district]
    if missing:
        raise RuntimeError(f"기초생보: 누락 자치구: {missing}")
    return [by_district[n] for n in SEOUL_DISTRICT_NAMES]


# ---------------------------------------------------------------------------
# D. 자치구별 지하·반지하주택 파서
# ---------------------------------------------------------------------------
# 구조: 단순 헤더 1행
#   자치구, 지하·반지하 주택, 노후 지하·반지하 주택, 노후 비율(%)
#
# 비율: 원본이 %(0~100) → 저장 시 /100 변환하여 0.0~1.0 저장

@dataclass(frozen=True)
class BasementRecord:
    district_name: str
    basement_household_count: Optional[int]
    aged_basement_household_count: Optional[int]
    aged_basement_household_ratio: Optional[float]   # 0.0~1.0
    source_note: str


def parse_basement_csv(
    data: bytes,
    encoding: str = DEFAULT_ENCODING,
    collection_date: str = "2026-04-03",
) -> list[BasementRecord]:
    rows = _open_csv_from_bytes(data, encoding)
    if len(rows) < 2:
        raise ValueError(f"지하반지하: 행 수 부족 ({len(rows)})")

    header = [_clean(h) for h in rows[0]]
    source_note = f"출처일 미표기; 수집일 {collection_date}"

    # 헤더 인덱스 동적 탐색
    district_col: Optional[int] = None
    basement_col: Optional[int] = None
    aged_col: Optional[int] = None
    ratio_col: Optional[int] = None

    for idx, h in enumerate(header):
        h_norm = h.replace(" ", "").replace("·", "")
        if "자치구" in h or "구" == h:
            district_col = idx
        elif "노후" not in h and ("지하반지하" in h_norm or "지하·반지하" in h):
            basement_col = idx
        elif "노후" in h and "비율" not in h and ("지하" in h):
            aged_col = idx
        elif "비율" in h or "%" in h:
            ratio_col = idx

    missing = []
    if district_col is None:
        missing.append("district_col(자치구)")
    if basement_col is None:
        missing.append("basement_col(지하·반지하 주택)")
    if missing:
        raise ValueError(f"지하반지하: 필수 컬럼 없음: {missing}. 헤더={header}")

    by_district: dict[str, BasementRecord] = {}
    for row_num, row in enumerate(rows[1:], start=2):
        if not row or len(row) <= district_col:
            continue
        district_name = _normalize_district_name(row[district_col])
        if district_name is None:
            continue

        raw_ratio = (
            _parse_float(row[ratio_col])
            if ratio_col is not None and ratio_col < len(row) else None
        )
        ratio_decimal = round(raw_ratio / 100.0, 8) if raw_ratio is not None else None

        by_district[district_name] = BasementRecord(
            district_name=district_name,
            basement_household_count=(
                _parse_int(row[basement_col]) if basement_col < len(row) else None
            ),
            aged_basement_household_count=(
                _parse_int(row[aged_col])
                if aged_col is not None and aged_col < len(row) else None
            ),
            aged_basement_household_ratio=ratio_decimal,
            source_note=source_note,
        )

    missing = [n for n in SEOUL_DISTRICT_NAMES if n not in by_district]
    if missing:
        raise RuntimeError(f"지하반지하: 누락 자치구: {missing}")
    return [by_district[n] for n in SEOUL_DISTRICT_NAMES]


# ---------------------------------------------------------------------------
# 통합 레코드
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class VulnerablePopRecord:
    district_name: str

    total_population: Optional[int]

    elderly_population_total: Optional[int]
    elderly_population_ratio: Optional[float]
    elderly_population_korean_total: Optional[int]
    elderly_population_foreign_total: Optional[int]

    disabled_population_total: Optional[int]
    disabled_population_ratio: Optional[float]
    disabled_population_male: Optional[int]
    disabled_population_female: Optional[int]

    basic_livelihood_recipient_total: Optional[int]
    basic_livelihood_recipient_ratio: Optional[float]
    basic_livelihood_household_count: Optional[int]

    basement_household_count: Optional[int]
    aged_basement_household_count: Optional[int]
    aged_basement_household_ratio: Optional[float]

    elderly_source_label: str
    elderly_source_year: int
    disabled_source_year: int
    basic_livelihood_source_year: int
    basement_source_note: str

    ingested_at: datetime


def merge_records(
    elderly: list[ElderlyRecord],
    disabled: list[DisabledRecord],
    basic: list[BasicLivelihoodRecord],
    basement: list[BasementRecord],
    ingested_at: datetime,
) -> list[VulnerablePopRecord]:
    elderly_map = {r.district_name: r for r in elderly}
    disabled_map = {r.district_name: r for r in disabled}
    basic_map = {r.district_name: r for r in basic}
    basement_map = {r.district_name: r for r in basement}

    result = []
    for name in SEOUL_DISTRICT_NAMES:
        e = elderly_map[name]
        d = disabled_map[name]
        b = basic_map[name]
        bm = basement_map[name]

        result.append(VulnerablePopRecord(
            district_name=name,
            total_population=e.total_population,

            elderly_population_total=e.elderly_population_total,
            elderly_population_ratio=_safe_ratio(e.elderly_population_total, e.total_population),
            elderly_population_korean_total=e.elderly_population_korean_total,
            elderly_population_foreign_total=e.elderly_population_foreign_total,

            disabled_population_total=d.disabled_population_total,
            # 분모=고령자현황 total_population (소스 시점 상이: 장애인 2024, 고령자 2025 Q4)
            disabled_population_ratio=_safe_ratio(d.disabled_population_total, e.total_population),
            disabled_population_male=d.disabled_population_male,
            disabled_population_female=d.disabled_population_female,

            basic_livelihood_recipient_total=b.basic_livelihood_recipient_total,
            # 분모=고령자현황 total_population (소스 시점 상이: 기초생보 2024, 고령자 2025 Q4)
            basic_livelihood_recipient_ratio=_safe_ratio(b.basic_livelihood_recipient_total, e.total_population),
            basic_livelihood_household_count=b.basic_livelihood_household_count,

            basement_household_count=bm.basement_household_count,
            aged_basement_household_count=bm.aged_basement_household_count,
            aged_basement_household_ratio=bm.aged_basement_household_ratio,

            elderly_source_label=e.source_label,
            elderly_source_year=e.source_year,
            disabled_source_year=d.source_year,
            basic_livelihood_source_year=b.source_year,
            basement_source_note=bm.source_note,

            ingested_at=ingested_at,
        ))
    return result


# ---------------------------------------------------------------------------
# DB 적재
# ---------------------------------------------------------------------------

UPSERT_SQL = """
INSERT INTO ref.seoul_vulnerable_population_district_snapshot (
    district_name,
    total_population,
    elderly_population_total,
    elderly_population_ratio,
    elderly_population_korean_total,
    elderly_population_foreign_total,
    disabled_population_total,
    disabled_population_ratio,
    disabled_population_male,
    disabled_population_female,
    basic_livelihood_recipient_total,
    basic_livelihood_recipient_ratio,
    basic_livelihood_household_count,
    basement_household_count,
    aged_basement_household_count,
    aged_basement_household_ratio,
    elderly_source_label,
    elderly_source_year,
    disabled_source_year,
    basic_livelihood_source_year,
    basement_source_note,
    source_name,
    ingested_at,
    updated_at
)
VALUES (
    %(district_name)s,
    %(total_population)s,
    %(elderly_population_total)s,
    %(elderly_population_ratio)s,
    %(elderly_population_korean_total)s,
    %(elderly_population_foreign_total)s,
    %(disabled_population_total)s,
    %(disabled_population_ratio)s,
    %(disabled_population_male)s,
    %(disabled_population_female)s,
    %(basic_livelihood_recipient_total)s,
    %(basic_livelihood_recipient_ratio)s,
    %(basic_livelihood_household_count)s,
    %(basement_household_count)s,
    %(aged_basement_household_count)s,
    %(aged_basement_household_ratio)s,
    %(elderly_source_label)s,
    %(elderly_source_year)s,
    %(disabled_source_year)s,
    %(basic_livelihood_source_year)s,
    %(basement_source_note)s,
    %(source_name)s,
    %(ingested_at)s,
    %(ingested_at)s
)
ON CONFLICT (district_name)
DO UPDATE SET
    total_population                    = EXCLUDED.total_population,
    elderly_population_total            = EXCLUDED.elderly_population_total,
    elderly_population_ratio            = EXCLUDED.elderly_population_ratio,
    elderly_population_korean_total     = EXCLUDED.elderly_population_korean_total,
    elderly_population_foreign_total    = EXCLUDED.elderly_population_foreign_total,
    disabled_population_total           = EXCLUDED.disabled_population_total,
    disabled_population_ratio           = EXCLUDED.disabled_population_ratio,
    disabled_population_male            = EXCLUDED.disabled_population_male,
    disabled_population_female          = EXCLUDED.disabled_population_female,
    basic_livelihood_recipient_total    = EXCLUDED.basic_livelihood_recipient_total,
    basic_livelihood_recipient_ratio    = EXCLUDED.basic_livelihood_recipient_ratio,
    basic_livelihood_household_count    = EXCLUDED.basic_livelihood_household_count,
    basement_household_count            = EXCLUDED.basement_household_count,
    aged_basement_household_count       = EXCLUDED.aged_basement_household_count,
    aged_basement_household_ratio       = EXCLUDED.aged_basement_household_ratio,
    elderly_source_label                = EXCLUDED.elderly_source_label,
    elderly_source_year                 = EXCLUDED.elderly_source_year,
    disabled_source_year                = EXCLUDED.disabled_source_year,
    basic_livelihood_source_year        = EXCLUDED.basic_livelihood_source_year,
    basement_source_note                = EXCLUDED.basement_source_note,
    source_name                         = EXCLUDED.source_name,
    updated_at                          = NOW()
"""


def upsert_records(records: list[VulnerablePopRecord], source_name: str) -> None:
    if not records:
        raise ValueError("적재할 레코드가 없음")

    prepared = [
        {
            "district_name": r.district_name,
            "total_population": r.total_population,
            "elderly_population_total": r.elderly_population_total,
            "elderly_population_ratio": r.elderly_population_ratio,
            "elderly_population_korean_total": r.elderly_population_korean_total,
            "elderly_population_foreign_total": r.elderly_population_foreign_total,
            "disabled_population_total": r.disabled_population_total,
            "disabled_population_ratio": r.disabled_population_ratio,
            "disabled_population_male": r.disabled_population_male,
            "disabled_population_female": r.disabled_population_female,
            "basic_livelihood_recipient_total": r.basic_livelihood_recipient_total,
            "basic_livelihood_recipient_ratio": r.basic_livelihood_recipient_ratio,
            "basic_livelihood_household_count": r.basic_livelihood_household_count,
            "basement_household_count": r.basement_household_count,
            "aged_basement_household_count": r.aged_basement_household_count,
            "aged_basement_household_ratio": r.aged_basement_household_ratio,
            "elderly_source_label": r.elderly_source_label,
            "elderly_source_year": r.elderly_source_year,
            "disabled_source_year": r.disabled_source_year,
            "basic_livelihood_source_year": r.basic_livelihood_source_year,
            "basement_source_note": r.basement_source_note,
            "source_name": source_name,
            "ingested_at": r.ingested_at,
        }
        for r in records
    ]

    with get_conn() as conn:
        with conn.cursor() as cur:
            execute_batch(cur, UPSERT_SQL, prepared, page_size=settings.db_batch_size)
        conn.commit()


# ---------------------------------------------------------------------------
# 검증
# ---------------------------------------------------------------------------

def validate_loaded(expected_count: int = 25) -> dict[str, object]:
    sql = """
    SELECT
        COUNT(*) AS row_count,
        COUNT(DISTINCT district_name) AS district_count,
        COUNT(*) FILTER (WHERE elderly_population_total IS NULL) AS null_elderly,
        COUNT(*) FILTER (WHERE disabled_population_total IS NULL) AS null_disabled,
        COUNT(*) FILTER (WHERE basic_livelihood_recipient_total IS NULL) AS null_basic,
        COUNT(*) FILTER (WHERE basement_household_count IS NULL) AS null_basement,
        COUNT(*) FILTER (WHERE elderly_population_ratio < 0 OR elderly_population_ratio > 1) AS ratio_out_of_range,
        MIN(elderly_source_year) AS min_elderly_year,
        MAX(elderly_source_year) AS max_elderly_year,
        MIN(disabled_source_year) AS min_disabled_year,
        MAX(disabled_source_year) AS max_disabled_year
    FROM ref.seoul_vulnerable_population_district_snapshot
    """
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
            row = cur.fetchone()

    keys = [
        "row_count", "district_count",
        "null_elderly", "null_disabled", "null_basic", "null_basement",
        "ratio_out_of_range",
        "min_elderly_year", "max_elderly_year",
        "min_disabled_year", "max_disabled_year",
    ]
    result = dict(zip(keys, row))

    if result["row_count"] != expected_count:
        raise RuntimeError(f"검증 실패: row_count={result['row_count']}, expected={expected_count}")
    if result["district_count"] != expected_count:
        raise RuntimeError(f"검증 실패: district_count={result['district_count']}, expected={expected_count}")
    if result["ratio_out_of_range"]:
        raise RuntimeError(f"검증 실패: ratio 범위 이탈 {result['ratio_out_of_range']}건")

    return result


# ---------------------------------------------------------------------------
# 진입점
# ---------------------------------------------------------------------------

def load_from_zip(zip_path: Path, encoding: str = DEFAULT_ENCODING) -> list[VulnerablePopRecord]:
    ingested_at = datetime.now(KST)
    csvs = _extract_csv_from_zip(zip_path)

    _, elderly_data = _find_csv(csvs, "고령자현황")
    _, disabled_data = _find_csv(csvs, "장애인")
    _, basic_data = _find_csv(csvs, "기초생활")
    _, basement_data = _find_csv(csvs, "지하반지하")

    elderly_records = parse_elderly_csv(elderly_data, encoding)
    disabled_records = parse_disabled_csv(disabled_data, encoding)
    basic_records = parse_basic_livelihood_csv(basic_data, encoding)
    basement_records = parse_basement_csv(basement_data, encoding)

    return merge_records(
        elderly=elderly_records,
        disabled=disabled_records,
        basic=basic_records,
        basement=basement_records,
        ingested_at=ingested_at,
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="서울 자치구 취약계층 밀집도 데이터를 ZIP에서 읽어 ref.seoul_vulnerable_population_district_snapshot에 적재."
    )
    parser.add_argument(
        "--zip",
        type=Path,
        default=DEFAULT_ZIP_PATH,
        help="입력 ZIP 경로 (기본: 프로젝트 루트/취약계층 밀집도 데이터.zip)",
    )
    parser.add_argument(
        "--encoding",
        default=DEFAULT_ENCODING,
        help="CSV 인코딩 (기본: utf-8-sig)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="파싱만 수행하고 DB 적재를 건너뜀",
    )
    args = parser.parse_args()

    zip_path = args.zip.resolve()
    if not zip_path.exists():
        raise FileNotFoundError(f"ZIP 파일을 찾을 수 없음: {zip_path}")

    print(f"[1/4] ZIP 파싱 시작: {zip_path}")
    records = load_from_zip(zip_path, args.encoding)
    print(f"      파싱 완료: {len(records)}개 자치구 레코드")

    # 샘플 출력
    print("\n[샘플 3행]")
    for r in records[:3]:
        print(
            f"  {r.district_name}: total={r.total_population:,}, "
            f"elderly={r.elderly_population_total:,}({r.elderly_population_ratio:.3%}), "
            f"disabled={r.disabled_population_total:,}, "
            f"basic={r.basic_livelihood_recipient_total:,}, "
            f"basement={r.basement_household_count:,}"
        )

    if args.dry_run:
        print("\n[dry-run] DB 적재를 건너뜁니다.")
        return

    print(f"\n[2/4] DB 적재 (upsert): ref.seoul_vulnerable_population_district_snapshot")
    upsert_records(records, source_name=zip_path.name)
    print("      적재 완료")

    print("\n[3/4] 검증")
    validation = validate_loaded()
    print(f"      {validation}")

    print(
        f"\n[4/4] 완료 — {len(records)}개 자치구 적재 | "
        f"고령자 소스: {records[0].elderly_source_label}({records[0].elderly_source_year}) | "
        f"장애인 소스년도: {records[0].disabled_source_year} | "
        f"기초생보 소스년도: {records[0].basic_livelihood_source_year}"
    )


if __name__ == "__main__":
    main()
