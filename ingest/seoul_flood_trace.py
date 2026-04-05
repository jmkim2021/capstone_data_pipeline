from __future__ import annotations

import argparse
import json
import re
import sys
import tempfile
import zipfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import geopandas as gpd
from psycopg2.extras import Json, execute_batch
from shapely.geometry import MultiPolygon, Polygon

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.append(str(PROJECT_ROOT))

from core.config import settings
from core.db import get_conn


KST = ZoneInfo("Asia/Seoul")
DEFAULT_SOURCE_DIR = settings.project_root / "연도별 침수흔적도"
SEOUL_DISTRICT_NAMES = [
    "종로구", "중구", "용산구", "성동구", "광진구", "동대문구", "중랑구",
    "성북구", "강북구", "도봉구", "노원구", "은평구", "서대문구", "마포구",
    "양천구", "강서구", "구로구", "금천구", "영등포구", "동작구", "관악구",
    "서초구", "강남구", "송파구", "강동구",
]
SEOUL_DISTRICT_BASE_NAMES = {name.removesuffix("구"): name for name in SEOUL_DISTRICT_NAMES}


@dataclass(frozen=True)
class FloodTraceRecord:
    source_year: int
    source_file_name: str
    layer_name: str
    feature_index: int
    pnu_text: str | None
    adm_cd: str | None
    district_name: str | None
    flood_zone_name: str | None
    damage_address: str | None
    property_type: str | None
    support_type: str | None
    disaster_name: str | None
    damage_reason_detail: str | None
    flood_start_date: str | None
    flood_end_date: str | None
    flood_start_time: str | None
    flood_end_time: str | None
    inundation_depth_m: float | None
    flooded_area_sqm: float | None
    avg_elevation_m: float | None
    inventory_year: str | None
    original_crs: str | None
    source_properties: dict[str, object | None]
    geom_wkt: str
    loaded_at: datetime


def _extract_year(path: Path) -> int:
    match = re.search(r"(20\d{2})", path.name)
    if not match:
        raise ValueError(f"Could not infer year from file name: {path.name}")
    return int(match.group(1))


def _clean_value(value: object) -> object | None:
    if value is None:
        return None
    try:
        if hasattr(value, "item"):
            value = value.item()
    except Exception:
        pass
    if isinstance(value, float) and value != value:
        return None
    if isinstance(value, str):
        value = value.strip()
        return value or None
    return value


def _to_float(value: object | None) -> float | None:
    value = _clean_value(value)
    if value is None:
        return None
    return float(value)


def _to_text(value: object | None) -> str | None:
    value = _clean_value(value)
    if value is None:
        return None
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def _to_multipolygon(geom):
    if geom is None or geom.is_empty:
        return None
    if isinstance(geom, MultiPolygon):
        return geom
    if isinstance(geom, Polygon):
        return MultiPolygon([geom])
    raise ValueError(f"Unsupported geometry type: {geom.geom_type}")


def _normalize_properties(row: dict[str, object]) -> dict[str, object | None]:
    return {str(key): _clean_value(value) for key, value in row.items()}


def _normalize_district_name(
    district_name: str | None,
    flood_zone_name: str | None,
    damage_address: str | None,
    adm_cd: str | None,
) -> str | None:
    candidates = [district_name, damage_address, flood_zone_name, adm_cd]

    for candidate in candidates:
        if not candidate:
            continue
        for gu_name in SEOUL_DISTRICT_NAMES:
            if gu_name in candidate:
                return gu_name

    if district_name:
        normalized = district_name.strip()
        if normalized in SEOUL_DISTRICT_BASE_NAMES:
            return SEOUL_DISTRICT_BASE_NAMES[normalized]
        if normalized.endswith("구"):
            return normalized

    return None


def _build_record(
    row: dict[str, object],
    source_year: int,
    source_file_name: str,
    layer_name: str,
    feature_index: int,
    original_crs: str | None,
    geom_wkt: str,
    loaded_at: datetime,
) -> FloodTraceRecord:
    props = _normalize_properties(row)
    damage_address = _to_text(props.get("피해위치(") or props.get("F_ZONE_NM"))
    flood_zone_name = _to_text(props.get("F_ZONE_NM"))
    district_name = _normalize_district_name(
        district_name=_to_text(props.get("GU_NAM")),
        flood_zone_name=flood_zone_name,
        damage_address=damage_address,
        adm_cd=_to_text(props.get("ADM_CD")),
    )

    return FloodTraceRecord(
        source_year=source_year,
        source_file_name=source_file_name,
        layer_name=layer_name,
        feature_index=feature_index,
        pnu_text=_to_text(props.get("PNU")),
        adm_cd=_to_text(props.get("ADM_CD")),
        district_name=district_name,
        flood_zone_name=flood_zone_name,
        damage_address=damage_address,
        property_type=_to_text(props.get("TYPE")),
        support_type=_to_text(props.get("TYPE2")),
        disaster_name=_to_text(props.get("F_DISA_NM")),
        damage_reason_detail=_to_text(props.get("F_RSN_DTL")),
        flood_start_date=_to_text(props.get("F_SAT_YMD") or props.get("피해일시")),
        flood_end_date=_to_text(props.get("F_END_YMD")),
        flood_start_time=_to_text(props.get("F_SAT_TM")),
        flood_end_time=_to_text(props.get("F_END_TM")),
        inundation_depth_m=_to_float(props.get("F_SHIM")),
        flooded_area_sqm=_to_float(props.get("F_AREA")),
        avg_elevation_m=_to_float(props.get("F_AVR_HGT")),
        inventory_year=_to_text(props.get("INV_YR") or props.get("F_YR")),
        original_crs=original_crs,
        source_properties=props,
        geom_wkt=geom_wkt,
        loaded_at=loaded_at,
    )


def load_records(source_dir: Path) -> list[FloodTraceRecord]:
    records: list[FloodTraceRecord] = []
    loaded_at = datetime.now(KST)

    for zip_path in sorted(source_dir.glob("*.zip")):
        source_year = _extract_year(zip_path)
        with tempfile.TemporaryDirectory() as tmp:
            with zipfile.ZipFile(zip_path) as zf:
                zf.extractall(tmp)

            for shp_path in sorted(Path(tmp).rglob("*.shp")):
                gdf = gpd.read_file(shp_path)
                original_crs = gdf.crs.to_string() if gdf.crs else None
                gdf = gdf.to_crs(epsg=4326)
                layer_name = shp_path.stem

                for feature_index, row in enumerate(gdf.itertuples(index=False), start=1):
                    row_map = row._asdict()
                    geom = _to_multipolygon(row_map.pop("geometry"))
                    if geom is None:
                        continue

                    record = _build_record(
                        row=row_map,
                        source_year=source_year,
                        source_file_name=zip_path.name,
                        layer_name=layer_name,
                        feature_index=feature_index,
                        original_crs=original_crs,
                        geom_wkt=geom.wkt,
                        loaded_at=loaded_at,
                    )
                    records.append(record)

    return records


def replace_records(records: list[FloodTraceRecord], source_file_names: list[str]) -> None:
    raw_insert_sql = """
    INSERT INTO raw.seoul_flood_trace_raw (
        source_year,
        source_file_name,
        layer_name,
        feature_index,
        original_crs,
        source_properties,
        geom,
        loaded_at
    )
    VALUES (
        %(source_year)s,
        %(source_file_name)s,
        %(layer_name)s,
        %(feature_index)s,
        %(original_crs)s,
        %(source_properties)s,
        ST_GeomFromText(%(geom_wkt)s, 4326),
        %(loaded_at)s
    )
    """

    ref_insert_sql = """
    INSERT INTO ref.seoul_flood_trace (
        source_year,
        source_file_name,
        layer_name,
        feature_index,
        pnu_text,
        adm_cd,
        district_name,
        flood_zone_name,
        damage_address,
        property_type,
        support_type,
        disaster_name,
        damage_reason_detail,
        flood_start_date,
        flood_end_date,
        flood_start_time,
        flood_end_time,
        inundation_depth_m,
        flooded_area_sqm,
        avg_elevation_m,
        inventory_year,
        original_crs,
        source_properties,
        geom,
        loaded_at,
        created_at,
        updated_at
    )
    VALUES (
        %(source_year)s,
        %(source_file_name)s,
        %(layer_name)s,
        %(feature_index)s,
        %(pnu_text)s,
        %(adm_cd)s,
        %(district_name)s,
        %(flood_zone_name)s,
        %(damage_address)s,
        %(property_type)s,
        %(support_type)s,
        %(disaster_name)s,
        %(damage_reason_detail)s,
        %(flood_start_date)s,
        %(flood_end_date)s,
        %(flood_start_time)s,
        %(flood_end_time)s,
        %(inundation_depth_m)s,
        %(flooded_area_sqm)s,
        %(avg_elevation_m)s,
        %(inventory_year)s,
        %(original_crs)s,
        %(source_properties)s,
        ST_GeomFromText(%(geom_wkt)s, 4326),
        %(loaded_at)s,
        %(loaded_at)s,
        %(loaded_at)s
    )
    """

    prepared_rows = [
        {
            "source_year": record.source_year,
            "source_file_name": record.source_file_name,
            "layer_name": record.layer_name,
            "feature_index": record.feature_index,
            "pnu_text": record.pnu_text,
            "adm_cd": record.adm_cd,
            "district_name": record.district_name,
            "flood_zone_name": record.flood_zone_name,
            "damage_address": record.damage_address,
            "property_type": record.property_type,
            "support_type": record.support_type,
            "disaster_name": record.disaster_name,
            "damage_reason_detail": record.damage_reason_detail,
            "flood_start_date": record.flood_start_date,
            "flood_end_date": record.flood_end_date,
            "flood_start_time": record.flood_start_time,
            "flood_end_time": record.flood_end_time,
            "inundation_depth_m": record.inundation_depth_m,
            "flooded_area_sqm": record.flooded_area_sqm,
            "avg_elevation_m": record.avg_elevation_m,
            "inventory_year": record.inventory_year,
            "original_crs": record.original_crs,
            "source_properties": Json(record.source_properties),
            "geom_wkt": record.geom_wkt,
            "loaded_at": record.loaded_at,
        }
        for record in records
    ]

    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM raw.seoul_flood_trace_raw WHERE source_file_name = ANY(%s)",
                (source_file_names,),
            )
            cur.execute(
                "DELETE FROM ref.seoul_flood_trace WHERE source_file_name = ANY(%s)",
                (source_file_names,),
            )
            execute_batch(cur, raw_insert_sql, prepared_rows, page_size=settings.db_batch_size)
            execute_batch(cur, ref_insert_sql, prepared_rows, page_size=settings.db_batch_size)
        conn.commit()


def main() -> None:
    parser = argparse.ArgumentParser(description="Load Seoul flood trace polygons into PostGIS.")
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=DEFAULT_SOURCE_DIR,
        help="Directory containing yearly zip files.",
    )
    args = parser.parse_args()

    source_dir = args.source_dir.resolve()
    if not source_dir.exists():
        raise FileNotFoundError(f"Source directory not found: {source_dir}")

    zip_files = sorted(source_dir.glob("*.zip"))
    if not zip_files:
        raise RuntimeError(f"No zip files found in: {source_dir}")

    records = load_records(source_dir)
    if not records:
        raise RuntimeError(f"No valid flood trace features found in: {source_dir}")

    replace_records(records, [path.name for path in zip_files])
    print(f"loaded {len(records)} flood trace features from {len(zip_files)} zip files")


if __name__ == "__main__":
    main()
