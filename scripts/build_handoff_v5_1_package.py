#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import math
import shutil
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent
TRAINSET_DIR = PROJECT_ROOT / "data" / "trainset"
HANDOFF_ROOT = PROJECT_ROOT / "handoff_v5_1"
PACKAGE_VERSION = "v5.1"
PACKAGE_DATE = "2026-04-03"
SOURCE_EXPORT_DATE = "20260402"

SOURCE_DATA_FILES = {
    "train_features_only.csv": TRAINSET_DIR / f"seoul_train_features_only_v5_1_aws_{SOURCE_EXPORT_DATE}.csv",
    "valid_features_only.csv": TRAINSET_DIR / f"seoul_valid_features_only_v5_1_aws_{SOURCE_EXPORT_DATE}.csv",
    "test_features_only.csv": TRAINSET_DIR / f"seoul_test_features_only_v5_1_aws_{SOURCE_EXPORT_DATE}.csv",
    "inference_features_latest.csv": TRAINSET_DIR / f"seoul_inference_features_latest_v5_1_aws_{SOURCE_EXPORT_DATE}.csv",
    "train_labels.csv": TRAINSET_DIR / f"seoul_train_labels_v5_1_aws_{SOURCE_EXPORT_DATE}.csv",
    "valid_labels.csv": TRAINSET_DIR / f"seoul_valid_labels_v5_1_aws_{SOURCE_EXPORT_DATE}.csv",
    "test_labels.csv": TRAINSET_DIR / f"seoul_test_labels_v5_1_aws_{SOURCE_EXPORT_DATE}.csv",
    "train_audit.csv": TRAINSET_DIR / f"seoul_train_audit_v5_1_aws_{SOURCE_EXPORT_DATE}.csv",
    "valid_audit.csv": TRAINSET_DIR / f"seoul_valid_audit_v5_1_aws_{SOURCE_EXPORT_DATE}.csv",
    "test_audit.csv": TRAINSET_DIR / f"seoul_test_audit_v5_1_aws_{SOURCE_EXPORT_DATE}.csv",
}

REFERENCE_FILES = {
    "reference/README.md": PROJECT_ROOT / "README.md",
    "reference/MODELING_HANDOFF.md": PROJECT_ROOT / "MODELING_HANDOFF.md",
}

SQL_FILES = {
    "sql/021_heavyrain_modelready_aws_v5_1_final.sql": PROJECT_ROOT / "sql" / "021_heavyrain_modelready_aws_v5_1_final.sql",
    "sql/021_heavyrain_modelready_aws_v5_1_validation_gates.sql": PROJECT_ROOT / "sql" / "021_heavyrain_modelready_aws_v5_1_validation_gates.sql",
    "sql/021_heavyrain_modelready_aws_v5_1_diagnostics.sql": PROJECT_ROOT / "sql" / "021_heavyrain_modelready_aws_v5_1_diagnostics.sql",
}

SCRIPT_FILES = {
    "scripts/export_seoul_district_heavyrain_modelready_v5_1_aws.py": PROJECT_ROOT / "scripts" / "export_seoul_district_heavyrain_modelready_v5_1_aws.py",
    "scripts/build_handoff_v5_1_package.py": PROJECT_ROOT / "scripts" / "build_handoff_v5_1_package.py",
}

DISTRICT_GRID_FILE = PROJECT_ROOT / "data" / "seoul_district_grids.csv"

FEATURE_ONLY_HEADER = [
    "district_name",
    "base_datetime",
    "temp_c",
    "precip_mm",
    "humidity_pct",
    "dew_point_c",
    "past_rain_3h_mm",
    "temp_change_3h_c",
    "humidity_change_3h_pct",
    "moist_energy",
]

LABEL_HEADER = [
    "district_name",
    "base_datetime",
    "label",
]

AUDIT_REQUIRED_COLUMNS = [
    "product_type",
    "district_name",
    "base_datetime",
    "target_datetime",
    "lead_minutes",
    "precip_mm_observed",
    "precip_mm_eff",
    "precip_raw_was_null",
    "temp_c",
    "humidity_pct_observed",
    "humidity_locf_raw",
    "humidity_imputed_pct",
    "humidity_used_default_prior",
    "humidity_raw_was_null",
    "dew_point_c",
    "past_rain_3h_mm",
    "temp_change_3h_c",
    "humidity_change_3h_pct",
    "moist_energy",
    "base_hour",
    "base_month",
    "day_of_week",
    "is_monsoon_season_flag",
    "hour_sin",
    "hour_cos",
    "month_sin",
    "month_cos",
    "is_model_input_ready",
    "label_window_end",
    "label_ready_at",
    "label_source_point_count",
    "target_rain_1h_mm",
    "target_rain_3h_mm",
    "label",
    "split_type",
    "label_source_name",
    "label_rule_name",
    "preprocessing_rule_name",
    "data_version",
]

MODEL_INPUT_HEADER = [
    "district_id",
    "district_name",
    "base_datetime",
    "base_hour",
    "base_month",
    "day_of_week",
    "is_monsoon_season_flag",
    "hour_sin",
    "hour_cos",
    "month_sin",
    "month_cos",
    "temp_c",
    "precip_mm",
    "humidity_pct",
    "dew_point_c",
    "past_rain_3h_mm",
    "temp_change_3h_c",
    "humidity_change_3h_pct",
    "moist_energy",
]


@dataclass
class ManifestEntry:
    file_path: str
    role: str
    source_path: str
    generation_method: str
    audience: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a DB-free v5.1 handoff package from existing exported CSV assets."
    )
    parser.add_argument(
        "--handoff-dir",
        default=str(HANDOFF_ROOT),
        help="Output directory for the handoff package. Defaults to project_root/handoff_v5_1",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Delete the existing handoff directory before rebuilding.",
    )
    parser.add_argument(
        "--from-db",
        action="store_true",
        help="If required source CSVs are missing, rerun the existing v5.1 DB export script first.",
    )
    return parser.parse_args()


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def read_header(path: Path) -> list[str]:
    with path.open("r", encoding="utf-8", newline="") as fp:
        reader = csv.reader(fp)
        return next(reader)


def write_text(path: Path, content: str) -> None:
    ensure_parent(path)
    path.write_text(content, encoding="utf-8")


def write_csv(path: Path, rows: list[dict[str, str]], fieldnames: list[str]) -> None:
    ensure_parent(path)
    with path.open("w", encoding="utf-8", newline="") as fp:
        writer = csv.DictWriter(fp, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def copy_file(src: Path, dst: Path, manifest: list[ManifestEntry], role: str, audience: str) -> None:
    ensure_parent(dst)
    shutil.copy2(src, dst)
    manifest.append(
        ManifestEntry(
            file_path=str(dst.relative_to(dst.parents[1])),
            role=role,
            source_path=str(src),
            generation_method="copy",
            audience=audience,
        )
    )


def format_number(value: float, digits: int = 6) -> str:
    text = f"{round(value, digits):.{digits}f}".rstrip("0").rstrip(".")
    if text in {"-0", "-0.0", ""}:
        return "0"
    return text


def parse_datetime(value: str) -> datetime:
    if len(value) >= 3 and value[-3] in {"+", "-"} and ":" not in value[-3:]:
        value = f"{value}00"
    return datetime.strptime(value, "%Y-%m-%d %H:%M:%S%z")


def sql_day_of_week(dt: datetime) -> int:
    return (dt.weekday() + 1) % 7


def parse_bool(value: str) -> bool:
    return value in {"t", "true", "True", "1", "y", "yes", "Y", "YES"}


def require_source_exports(from_db: bool) -> None:
    missing = [path for path in SOURCE_DATA_FILES.values() if not path.exists()]
    if not missing:
        return
    if from_db:
        export_script = PROJECT_ROOT / "scripts" / "export_seoul_district_heavyrain_modelready_v5_1_aws.py"
        cmd = [sys.executable, str(export_script)]
        subprocess.run(cmd, cwd=str(PROJECT_ROOT), check=True)
        missing = [path for path in SOURCE_DATA_FILES.values() if not path.exists()]
        if not missing:
            return
    missing_text = "\n".join(str(path) for path in missing)
    raise FileNotFoundError(
        "Required v5.1 source exports are missing.\n"
        f"{missing_text}\n"
        "Run this script with --from-db or regenerate the exports with "
        "scripts/export_seoul_district_heavyrain_modelready_v5_1_aws.py first."
    )


def read_distinct_districts(path: Path) -> list[str]:
    with path.open("r", encoding="utf-8", newline="") as fp:
        reader = csv.DictReader(fp)
        districts = sorted({row["district_name"] for row in reader})
    return districts


def build_district_index() -> list[dict[str, str]]:
    train_districts = read_distinct_districts(SOURCE_DATA_FILES["train_features_only.csv"])
    valid_districts = read_distinct_districts(SOURCE_DATA_FILES["valid_features_only.csv"])
    test_districts = read_distinct_districts(SOURCE_DATA_FILES["test_features_only.csv"])
    inference_districts = read_distinct_districts(SOURCE_DATA_FILES["inference_features_latest.csv"])

    if not (train_districts == valid_districts == test_districts == inference_districts):
        raise ValueError("Distinct district lists do not match across splits and inference exports.")
    if "종로구" in train_districts:
        raise ValueError("v5.1 stable district universe should exclude 종로구, but 종로구 was found.")
    if len(train_districts) != 24:
        raise ValueError(f"Expected 24 stable districts, found {len(train_districts)}.")

    return [
        {"district_id": str(idx), "district_name": district_name}
        for idx, district_name in enumerate(train_districts)
    ]


def verify_headers() -> None:
    for key in [
        "train_features_only.csv",
        "valid_features_only.csv",
        "test_features_only.csv",
        "inference_features_latest.csv",
    ]:
        header = read_header(SOURCE_DATA_FILES[key])
        if header != FEATURE_ONLY_HEADER:
            raise ValueError(f"Unexpected feature-only header in {SOURCE_DATA_FILES[key]}")

    for key in ["train_labels.csv", "valid_labels.csv", "test_labels.csv"]:
        header = read_header(SOURCE_DATA_FILES[key])
        if header != LABEL_HEADER:
            raise ValueError(f"Unexpected label header in {SOURCE_DATA_FILES[key]}")

    for key in ["train_audit.csv", "valid_audit.csv", "test_audit.csv"]:
        header = read_header(SOURCE_DATA_FILES[key])
        if header != AUDIT_REQUIRED_COLUMNS:
            raise ValueError(f"Unexpected audit header in {SOURCE_DATA_FILES[key]}")


def derive_model_input_row(row: dict[str, str], district_id: str) -> dict[str, str]:
    dt = parse_datetime(row["base_datetime"])
    base_hour = dt.hour
    base_month = dt.month
    day_of_week = sql_day_of_week(dt)
    is_monsoon = 1 if 6 <= base_month <= 9 else 0
    hour_angle = 2.0 * math.pi * base_hour / 24.0
    month_angle = 2.0 * math.pi * base_month / 12.0

    return {
        "district_id": district_id,
        "district_name": row["district_name"],
        "base_datetime": row["base_datetime"],
        "base_hour": str(base_hour),
        "base_month": str(base_month),
        "day_of_week": str(day_of_week),
        "is_monsoon_season_flag": str(is_monsoon),
        "hour_sin": format_number(math.sin(hour_angle)),
        "hour_cos": format_number(math.cos(hour_angle)),
        "month_sin": format_number(math.sin(month_angle)),
        "month_cos": format_number(math.cos(month_angle)),
        "temp_c": row["temp_c"],
        "precip_mm": row["precip_mm"],
        "humidity_pct": row["humidity_pct"],
        "dew_point_c": row["dew_point_c"],
        "past_rain_3h_mm": row["past_rain_3h_mm"],
        "temp_change_3h_c": row["temp_change_3h_c"],
        "humidity_change_3h_pct": row["humidity_change_3h_pct"],
        "moist_energy": row["moist_energy"],
    }


def generate_model_input(
    feature_path: Path,
    output_path: Path,
    district_to_id: dict[str, str],
    manifest: list[ManifestEntry],
    role: str,
    audience: str,
) -> tuple[int, list[str]]:
    ensure_parent(output_path)
    row_count = 0
    with feature_path.open("r", encoding="utf-8", newline="") as src, output_path.open(
        "w", encoding="utf-8", newline=""
    ) as dst:
        reader = csv.DictReader(src)
        writer = csv.DictWriter(dst, fieldnames=MODEL_INPUT_HEADER)
        writer.writeheader()
        for row in reader:
            district_name = row["district_name"]
            if district_name not in district_to_id:
                raise KeyError(f"District {district_name} is missing from district index.")
            writer.writerow(derive_model_input_row(row, district_to_id[district_name]))
            row_count += 1

    manifest.append(
        ManifestEntry(
            file_path=str(output_path.relative_to(output_path.parents[1])),
            role=role,
            source_path=str(feature_path),
            generation_method="generated_from_feature_only_csv",
            audience=audience,
        )
    )
    return row_count, MODEL_INPUT_HEADER.copy()


def count_lines_minus_header(path: Path) -> int:
    with path.open("r", encoding="utf-8", newline="") as fp:
        next(fp)
        return sum(1 for _ in fp)


def compare_key_alignment(left_path: Path, right_path: Path) -> bool:
    with left_path.open("r", encoding="utf-8", newline="") as left_fp, right_path.open(
        "r", encoding="utf-8", newline=""
    ) as right_fp:
        left_reader = csv.DictReader(left_fp)
        right_reader = csv.DictReader(right_fp)
        for left_row, right_row in zip(left_reader, right_reader):
            left_key = (left_row["district_name"], left_row["base_datetime"])
            right_key = (right_row["district_name"], right_row["base_datetime"])
            if left_key != right_key:
                return False
        return count_lines_minus_header(left_path) == count_lines_minus_header(right_path)


def summarize_labels(path: Path) -> dict[str, str]:
    rows = 0
    positives = 0
    districts = set()
    months = set()
    prev_key: tuple[str, str] | None = None
    duplicate_key_groups = 0
    with path.open("r", encoding="utf-8", newline="") as fp:
        reader = csv.DictReader(fp)
        for row in reader:
            rows += 1
            positives += int(row["label"])
            districts.add(row["district_name"])
            months.add(row["base_datetime"][:7])
            key = (row["district_name"], row["base_datetime"])
            if key == prev_key:
                duplicate_key_groups += 1
            prev_key = key
    return {
        "rows": str(rows),
        "positive_rows": str(positives),
        "positive_rate": f"{(positives / rows):.6f}",
        "district_count": str(len(districts)),
        "month_count": str(len(months)),
        "duplicate_key_groups": str(duplicate_key_groups),
    }


def summarize_audit(path: Path) -> dict[str, str]:
    rows = 0
    ready_rows = 0
    districts = set()
    months = set()
    label_rule_names = set()
    preprocessing_rule_names = set()
    data_versions = set()
    label_source_names = set()
    drop_reason_counts: Counter[str] = Counter()
    with path.open("r", encoding="utf-8", newline="") as fp:
        reader = csv.DictReader(fp)
        for row in reader:
            rows += 1
            districts.add(row["district_name"])
            months.add(row["base_datetime"][:7])
            label_rule_names.add(row["label_rule_name"])
            preprocessing_rule_names.add(row["preprocessing_rule_name"])
            data_versions.add(row["data_version"])
            label_source_names.add(row["label_source_name"])
            if parse_bool(row["is_model_input_ready"]):
                ready_rows += 1
            else:
                if row["temp_c"] == "":
                    drop_reason_counts["temp_c_null"] += 1
                if row["dew_point_c"] == "":
                    drop_reason_counts["dew_point_c_null"] += 1
                if row["temp_change_3h_c"] == "":
                    drop_reason_counts["temp_change_3h_c_null"] += 1
                if row["humidity_change_3h_pct"] == "":
                    drop_reason_counts["humidity_change_3h_pct_null"] += 1
                if row["moist_energy"] == "":
                    drop_reason_counts["moist_energy_null"] += 1
    drop_rows = rows - ready_rows
    return {
        "rows": str(rows),
        "ready_rows": str(ready_rows),
        "drop_rows": str(drop_rows),
        "drop_rate": f"{(drop_rows / rows):.6f}",
        "district_count": str(len(districts)),
        "month_count": str(len(months)),
        "label_rule_name": sorted(label_rule_names)[0],
        "preprocessing_rule_name": sorted(preprocessing_rule_names)[0],
        "data_version": sorted(data_versions)[0],
        "label_source_name": sorted(label_source_names)[0],
        "drop_temp_c_null": str(drop_reason_counts["temp_c_null"]),
        "drop_dew_point_c_null": str(drop_reason_counts["dew_point_c_null"]),
        "drop_temp_change_3h_c_null": str(drop_reason_counts["temp_change_3h_c_null"]),
        "drop_humidity_change_3h_pct_null": str(drop_reason_counts["humidity_change_3h_pct_null"]),
        "drop_moist_energy_null": str(drop_reason_counts["moist_energy_null"]),
    }


def summarize_features(path: Path) -> dict[str, str]:
    rows = 0
    districts = set()
    months = set()
    prev_key: tuple[str, str] | None = None
    duplicate_key_groups = 0
    with path.open("r", encoding="utf-8", newline="") as fp:
        reader = csv.DictReader(fp)
        for row in reader:
            rows += 1
            districts.add(row["district_name"])
            months.add(row["base_datetime"][:7])
            key = (row["district_name"], row["base_datetime"])
            if key == prev_key:
                duplicate_key_groups += 1
            prev_key = key
    return {
        "rows": str(rows),
        "district_count": str(len(districts)),
        "month_count": str(len(months)),
        "duplicate_key_groups": str(duplicate_key_groups),
    }


def build_feature_dictionary_rows() -> list[dict[str, str]]:
    return [
        {"column_name": "district_id", "role": "categorical_id", "dtype": "integer", "included_in_model_input": "yes", "recommended_for_numeric_matrix": "yes", "description": "Stable 24-district zero-based integer ID sorted by district_name.", "notes": "See metadata/district_index.csv."},
        {"column_name": "district_name", "role": "join_key", "dtype": "string", "included_in_model_input": "yes", "recommended_for_numeric_matrix": "no", "description": "District name used for joins, grouping, and provenance.", "notes": "Keep for debugging even if excluded from X matrix."},
        {"column_name": "base_datetime", "role": "join_key", "dtype": "timestamp_tz", "included_in_model_input": "yes", "recommended_for_numeric_matrix": "no", "description": "Feature base timestamp in Asia/Seoul timezone.", "notes": "Primary join key with labels and audit."},
        {"column_name": "base_hour", "role": "calendar_feature", "dtype": "integer", "included_in_model_input": "yes", "recommended_for_numeric_matrix": "yes", "description": "Hour extracted from base_datetime.", "notes": "Also keep hour_sin/hour_cos for cyclical encoding."},
        {"column_name": "base_month", "role": "calendar_feature", "dtype": "integer", "included_in_model_input": "yes", "recommended_for_numeric_matrix": "yes", "description": "Month extracted from base_datetime.", "notes": "Also keep month_sin/month_cos for cyclical encoding."},
        {"column_name": "day_of_week", "role": "calendar_feature", "dtype": "integer", "included_in_model_input": "yes", "recommended_for_numeric_matrix": "yes", "description": "SQL-style day of week where Sunday=0.", "notes": "Derived to match the final SQL exactly."},
        {"column_name": "is_monsoon_season_flag", "role": "calendar_feature", "dtype": "integer", "included_in_model_input": "yes", "recommended_for_numeric_matrix": "yes", "description": "Binary flag for months 6 through 9.", "notes": "Matches final SQL monsoon rule."},
        {"column_name": "hour_sin", "role": "cyclical_time_feature", "dtype": "float", "included_in_model_input": "yes", "recommended_for_numeric_matrix": "yes", "description": "Sine transform of base_hour using 24-hour cycle.", "notes": "Train and serve must use identical transform."},
        {"column_name": "hour_cos", "role": "cyclical_time_feature", "dtype": "float", "included_in_model_input": "yes", "recommended_for_numeric_matrix": "yes", "description": "Cosine transform of base_hour using 24-hour cycle.", "notes": "Train and serve must use identical transform."},
        {"column_name": "month_sin", "role": "cyclical_time_feature", "dtype": "float", "included_in_model_input": "yes", "recommended_for_numeric_matrix": "yes", "description": "Sine transform of base_month using 12-month cycle.", "notes": "Derived from month number 1..12."},
        {"column_name": "month_cos", "role": "cyclical_time_feature", "dtype": "float", "included_in_model_input": "yes", "recommended_for_numeric_matrix": "yes", "description": "Cosine transform of base_month using 12-month cycle.", "notes": "Derived from month number 1..12."},
        {"column_name": "temp_c", "role": "weather_feature", "dtype": "float", "included_in_model_input": "yes", "recommended_for_numeric_matrix": "yes", "description": "Observed hourly AWS temperature in Celsius.", "notes": "Raw source is std.seoul_aws_district_hourly."},
        {"column_name": "precip_mm", "role": "weather_feature", "dtype": "float", "included_in_model_input": "yes", "recommended_for_numeric_matrix": "yes", "description": "Effective hourly precipitation after null-to-zero preprocessing.", "notes": "Original observed value is preserved in audit as precip_mm_observed."},
        {"column_name": "humidity_pct", "role": "weather_feature", "dtype": "float", "included_in_model_input": "yes", "recommended_for_numeric_matrix": "yes", "description": "Effective humidity after LOCF and default-65 imputation.", "notes": "Observed and imputed fields are both present in audit."},
        {"column_name": "dew_point_c", "role": "derived_feature", "dtype": "float", "included_in_model_input": "yes", "recommended_for_numeric_matrix": "yes", "description": "Dew point derived from temp_c and imputed humidity using Magnus formula.", "notes": "Null only when upstream fields are unusable."},
        {"column_name": "past_rain_3h_mm", "role": "derived_feature", "dtype": "float", "included_in_model_input": "yes", "recommended_for_numeric_matrix": "yes", "description": "Past 3-hour accumulated rain using current and previous two hourly precipitation values.", "notes": "Use this instead of future target_rain_3h_mm."},
        {"column_name": "temp_change_3h_c", "role": "derived_feature", "dtype": "float", "included_in_model_input": "yes", "recommended_for_numeric_matrix": "yes", "description": "Temperature change versus three hours earlier.", "notes": "Rows missing this field are excluded from model_input."},
        {"column_name": "humidity_change_3h_pct", "role": "derived_feature", "dtype": "float", "included_in_model_input": "yes", "recommended_for_numeric_matrix": "yes", "description": "Humidity change versus three hours earlier after imputation.", "notes": "Rows missing this field are excluded from model_input."},
        {"column_name": "moist_energy", "role": "derived_feature", "dtype": "float", "included_in_model_input": "yes", "recommended_for_numeric_matrix": "yes", "description": "Simple interaction feature defined as temp_c * humidity_pct / 100.", "notes": "Rows missing this field are excluded from model_input."},
    ]


def build_audit_dictionary_rows() -> list[dict[str, str]]:
    return [
        {"column_name": "product_type", "category": "provenance", "dtype": "string", "analysis_use": "dataset_scope", "description": "Source product type for the row.", "notes": "Current v5.1 exports use aws_hourly."},
        {"column_name": "district_name", "category": "key", "dtype": "string", "analysis_use": "join_and_group", "description": "District key.", "notes": "Join with labels, features, and model_input."},
        {"column_name": "base_datetime", "category": "key", "dtype": "timestamp_tz", "analysis_use": "join_and_timeline", "description": "Feature base timestamp.", "notes": "Primary join key with labels and model_input."},
        {"column_name": "target_datetime", "category": "timeline", "dtype": "timestamp_tz", "analysis_use": "lead_reference", "description": "Target datetime aligned with the current feature row.", "notes": "Lead is always 0 in this export."},
        {"column_name": "lead_minutes", "category": "timeline", "dtype": "integer", "analysis_use": "lead_reference", "description": "Forecast lead in minutes.", "notes": "Current export is 0 only."},
        {"column_name": "precip_mm_observed", "category": "observed_feature", "dtype": "float", "analysis_use": "raw_value_trace", "description": "Original observed hourly precipitation before preprocessing.", "notes": "Nulls are replaced with 0 in precip_mm_eff."},
        {"column_name": "precip_mm_eff", "category": "effective_feature", "dtype": "float", "analysis_use": "model_input_trace", "description": "Effective precipitation used for downstream feature generation.", "notes": "This is the value copied into feature-only/model_input precip_mm."},
        {"column_name": "precip_raw_was_null", "category": "missingness_flag", "dtype": "boolean", "analysis_use": "quality_audit", "description": "Whether raw precipitation was null.", "notes": "True means precip_mm_eff was filled with 0."},
        {"column_name": "temp_c", "category": "effective_feature", "dtype": "float", "analysis_use": "model_input_trace", "description": "Observed hourly temperature.", "notes": "If null, row becomes not ready."},
        {"column_name": "humidity_pct_observed", "category": "observed_feature", "dtype": "float", "analysis_use": "raw_value_trace", "description": "Original observed humidity before imputation.", "notes": "May be null."},
        {"column_name": "humidity_locf_raw", "category": "intermediate_feature", "dtype": "float", "analysis_use": "imputation_trace", "description": "Last observation carried forward humidity value before default fallback.", "notes": "Null when no prior humidity exists."},
        {"column_name": "humidity_imputed_pct", "category": "effective_feature", "dtype": "float", "analysis_use": "model_input_trace", "description": "Humidity after LOCF and default-65 imputation.", "notes": "This is the value copied into feature-only/model_input humidity_pct."},
        {"column_name": "humidity_used_default_prior", "category": "missingness_flag", "dtype": "boolean", "analysis_use": "quality_audit", "description": "Whether default 65 was used because both raw and LOCF humidity were unavailable.", "notes": "Important for early-time or sparse segments."},
        {"column_name": "humidity_raw_was_null", "category": "missingness_flag", "dtype": "boolean", "analysis_use": "quality_audit", "description": "Whether raw humidity was null.", "notes": "True even when LOCF resolved the final value."},
        {"column_name": "dew_point_c", "category": "derived_feature", "dtype": "float", "analysis_use": "drop_reason_trace", "description": "Dew point derived from temperature and effective humidity.", "notes": "Null rows are excluded from model_input."},
        {"column_name": "past_rain_3h_mm", "category": "derived_feature", "dtype": "float", "analysis_use": "model_input_trace", "description": "Past 3-hour accumulated precipitation.", "notes": "Safe feature, not a future label."},
        {"column_name": "temp_change_3h_c", "category": "derived_feature", "dtype": "float", "analysis_use": "drop_reason_trace", "description": "Temperature delta from three hours earlier.", "notes": "Null rows are excluded from model_input."},
        {"column_name": "humidity_change_3h_pct", "category": "derived_feature", "dtype": "float", "analysis_use": "drop_reason_trace", "description": "Humidity delta from three hours earlier after imputation.", "notes": "Null rows are excluded from model_input."},
        {"column_name": "moist_energy", "category": "derived_feature", "dtype": "float", "analysis_use": "drop_reason_trace", "description": "Interaction feature temp_c * humidity_pct / 100.", "notes": "Null rows are excluded from model_input."},
        {"column_name": "base_hour", "category": "calendar_feature", "dtype": "integer", "analysis_use": "time_analysis", "description": "Hour extracted from base_datetime.", "notes": "Included in audit to reproduce model_input."},
        {"column_name": "base_month", "category": "calendar_feature", "dtype": "integer", "analysis_use": "seasonality_analysis", "description": "Month extracted from base_datetime.", "notes": "Included in audit to reproduce model_input."},
        {"column_name": "day_of_week", "category": "calendar_feature", "dtype": "integer", "analysis_use": "seasonality_analysis", "description": "SQL-style day of week with Sunday=0.", "notes": "Included in audit to reproduce model_input."},
        {"column_name": "is_monsoon_season_flag", "category": "calendar_feature", "dtype": "boolean", "analysis_use": "seasonality_analysis", "description": "Whether the row falls in months 6..9.", "notes": "Model_input uses integer 0/1."},
        {"column_name": "hour_sin", "category": "calendar_feature", "dtype": "float", "analysis_use": "schema_reproduction", "description": "24-hour sine encoding.", "notes": "Matches final SQL model_input."},
        {"column_name": "hour_cos", "category": "calendar_feature", "dtype": "float", "analysis_use": "schema_reproduction", "description": "24-hour cosine encoding.", "notes": "Matches final SQL model_input."},
        {"column_name": "month_sin", "category": "calendar_feature", "dtype": "float", "analysis_use": "schema_reproduction", "description": "12-month sine encoding.", "notes": "Matches final SQL model_input."},
        {"column_name": "month_cos", "category": "calendar_feature", "dtype": "float", "analysis_use": "schema_reproduction", "description": "12-month cosine encoding.", "notes": "Matches final SQL model_input."},
        {"column_name": "is_model_input_ready", "category": "validation_flag", "dtype": "boolean", "analysis_use": "drop_filter", "description": "Whether the row is eligible for feature-only/model_input export.", "notes": "False rows explain drops from audit to feature-only."},
        {"column_name": "label_window_end", "category": "label_timeline", "dtype": "timestamp_tz", "analysis_use": "label_window_trace", "description": "End of the future 3-hour label window.", "notes": "base_datetime + 3 hours."},
        {"column_name": "label_ready_at", "category": "label_timeline", "dtype": "timestamp_tz", "analysis_use": "pending_boundary", "description": "Time after which the label is considered ready.", "notes": "base_datetime + 3 hours 20 minutes."},
        {"column_name": "label_source_point_count", "category": "label_provenance", "dtype": "integer", "analysis_use": "label_quality", "description": "Number of source hourly points available for the future label window.", "notes": "Expected 3 for ready labeled rows."},
        {"column_name": "target_rain_1h_mm", "category": "label_value", "dtype": "float", "analysis_use": "eda_and_error_analysis", "description": "Future 1-hour rain target at lead 0.", "notes": "Leakage column, never include in feature table."},
        {"column_name": "target_rain_3h_mm", "category": "label_value", "dtype": "float", "analysis_use": "eda_and_error_analysis", "description": "Future 3-hour accumulated rain target at lead 0.", "notes": "Leakage column, never include in feature table."},
        {"column_name": "label", "category": "label_value", "dtype": "integer", "analysis_use": "training_target", "description": "Binary heavy-rain flag.", "notes": "Rule is documented in metadata/label_policy.txt."},
        {"column_name": "split_type", "category": "split_provenance", "dtype": "string", "analysis_use": "split_check", "description": "Time-based split assignment.", "notes": "Expected values are train, valid, or test."},
        {"column_name": "label_source_name", "category": "label_provenance", "dtype": "string", "analysis_use": "source_trace", "description": "Recorded source table used to compute the label.", "notes": "Current v5.1 exports show std.seoul_aws_district_hourly."},
        {"column_name": "label_rule_name", "category": "label_provenance", "dtype": "string", "analysis_use": "policy_check", "description": "Exact label rule identifier.", "notes": "Expected fixed value is 1h>=20 or 3h>=40 with lead 0..3."},
        {"column_name": "preprocessing_rule_name", "category": "preprocessing_provenance", "dtype": "string", "analysis_use": "policy_check", "description": "Exact preprocessing rule identifier.", "notes": "Expected fixed value is aws_hourly_precip0_humidity_locf_default65_v5_1."},
        {"column_name": "data_version", "category": "versioning", "dtype": "string", "analysis_use": "snapshot_trace", "description": "Dataset version string embedded in the export.", "notes": "Expected fixed value is seoul_district_heavyrain_v5_1_aws_final."},
    ]


def build_export_model_input_sql() -> str:
    return """\\copy (
SELECT *
FROM mart.hrain_v5_1_aws_train_model_input_20260402
ORDER BY district_name, base_datetime
) TO 'handoff_v5_1/data/train_model_input.csv' CSV HEADER;

\\copy (
SELECT *
FROM mart.hrain_v5_1_aws_valid_model_input_20260402
ORDER BY district_name, base_datetime
) TO 'handoff_v5_1/data/valid_model_input.csv' CSV HEADER;

\\copy (
SELECT *
FROM mart.hrain_v5_1_aws_test_model_input_20260402
ORDER BY district_name, base_datetime
) TO 'handoff_v5_1/data/test_model_input.csv' CSV HEADER;

\\copy (
SELECT *
FROM mart.hrain_v5_1_aws_inference_model_input_latest_20260402
ORDER BY district_name, base_datetime
) TO 'handoff_v5_1/data/inference_model_input_latest.csv' CSV HEADER;
"""


def build_export_audit_sql() -> str:
    return """\\copy (
SELECT *
FROM mart.hrain_v5_1_aws_train_audit_20260402
ORDER BY district_name, base_datetime
) TO 'handoff_v5_1/data/train_audit.csv' CSV HEADER;

\\copy (
SELECT *
FROM mart.hrain_v5_1_aws_valid_audit_20260402
ORDER BY district_name, base_datetime
) TO 'handoff_v5_1/data/valid_audit.csv' CSV HEADER;

\\copy (
SELECT *
FROM mart.hrain_v5_1_aws_test_audit_20260402
ORDER BY district_name, base_datetime
) TO 'handoff_v5_1/data/test_audit.csv' CSV HEADER;
"""


def build_readme_for_modeling(
    district_index_rows: list[dict[str, str]],
    split_metrics: dict[str, dict[str, str]],
) -> str:
    districts = ", ".join(row["district_name"] for row in district_index_rows)
    return f"""v5.1 모델링 handoff 패키지 안내

이 폴더는 DB 없이도 바로 학습을 시작할 수 있도록 구성한 v5.1 학습셋 인계 패키지입니다.
가장 먼저 볼 파일은 아래 순서입니다.

1. data/train_model_input.csv
2. data/train_labels.csv
3. metadata/feature_dictionary.csv
4. metadata/label_policy.txt
5. metadata/split_policy.txt
6. metadata/district_index.csv
7. data/inference_model_input_latest.csv

바로 학습할 때 쓰는 파일
- 학습 입력: data/train_model_input.csv
- 검증 입력: data/valid_model_input.csv
- 테스트 입력: data/test_model_input.csv
- 학습 라벨: data/train_labels.csv
- 검증 라벨: data/valid_labels.csv
- 테스트 라벨: data/test_labels.csv
- 최신 추론 입력: data/inference_model_input_latest.csv

조인 키
- district_name
- base_datetime

중요
- train_model_input / valid_model_input / test_model_input 은 기존 feature-only CSV에서 district_id 와 시간 파생 컬럼을 추가해 만든 최종 모델 입력본입니다.
- feature-only CSV만 사용하면 district_id, base_hour, base_month, day_of_week, hour_sin, hour_cos, month_sin, month_cos, is_monsoon_season_flag 가 빠지므로 train/serve 전처리 일관성을 직접 다시 구현해야 합니다.
- district_name 과 base_datetime 은 조인과 추적용 컬럼입니다. 일반적인 수치 모델 X matrix 에서는 제외하거나 별도 인코딩하십시오.
- district_id 는 district_name 의 안정적인 정수 매핑입니다. 매핑은 metadata/district_index.csv 에 고정되어 있습니다.
- inference_model_input_latest.csv 의 컬럼 순서는 학습용 model_input 과 동일합니다.

권장 입력 컬럼
- district_id
- base_hour
- base_month
- day_of_week
- is_monsoon_season_flag
- hour_sin
- hour_cos
- month_sin
- month_cos
- temp_c
- precip_mm
- humidity_pct
- dew_point_c
- past_rain_3h_mm
- temp_change_3h_c
- humidity_change_3h_pct
- moist_energy

권장 제외 컬럼
- district_name
- base_datetime

클래스 불균형 요약
- train: {split_metrics["train"]["positive_rows"]} positive / {split_metrics["train"]["label_rows"]} rows ({split_metrics["train"]["positive_rate"]})
- valid: {split_metrics["valid"]["positive_rows"]} positive / {split_metrics["valid"]["label_rows"]} rows ({split_metrics["valid"]["positive_rate"]})
- test: {split_metrics["test"]["positive_rows"]} positive / {split_metrics["test"]["label_rows"]} rows ({split_metrics["test"]["positive_rate"]})

stable district universe
- 총 24개 구
- 종로구 제외
- 순서: {districts}

주의사항
- 현재 패키지 기준 라벨 원천은 audit CSV 와 final SQL 에 기록된 std.seoul_aws_district_hourly 입니다.
- 기존 상위 문서 중 일부에는 서울시 강우량 기반이라고 적힌 구간이 있으나, 이 패키지에서는 실제 export 결과를 source of truth 로 사용합니다.
- leakage 방지를 위해 target_rain_1h_mm, target_rain_3h_mm, label 컬럼은 model_input CSV 에 포함하지 않았습니다.

참고 파일
- data/train_features_only.csv, data/valid_features_only.csv, data/test_features_only.csv
- data/inference_features_latest.csv
- data/train_audit.csv, data/valid_audit.csv, data/test_audit.csv
- metadata/class_balance_summary.csv
- metadata/validation_summary.txt
"""


def build_readme_for_analysis(
    district_index_rows: list[dict[str, str]],
    audit_metrics: dict[str, dict[str, str]],
) -> str:
    districts = ", ".join(row["district_name"] for row in district_index_rows)
    return f"""v5.1 분석 handoff 패키지 안내

이 폴더는 DB 없이도 품질 점검, EDA, 라벨 검증, 전처리 추적, drop 원인 분석을 바로 시작할 수 있도록 구성한 분석용 인계 패키지입니다.
가장 먼저 볼 파일은 아래 순서입니다.

1. data/train_audit.csv
2. metadata/audit_dictionary.csv
3. metadata/label_policy.txt
4. metadata/preprocessing_spec.txt
5. metadata/split_policy.txt
6. metadata/validation_summary.txt
7. metadata/drop_reason_summary.csv

분석 시작용 핵심 파일
- 전체 provenance/품질 추적: data/train_audit.csv, data/valid_audit.csv, data/test_audit.csv
- 전처리 규칙 사전: metadata/audit_dictionary.csv
- 라벨 규칙: metadata/label_policy.txt
- split 범위: metadata/split_policy.txt
- district universe: metadata/district_universe.txt
- validation 결과 요약: metadata/validation_summary.txt

audit CSV 에서 바로 확인 가능한 항목
- observed/raw 값: precip_mm_observed, humidity_pct_observed
- effective/imputed 값: precip_mm_eff, humidity_imputed_pct, humidity_locf_raw
- missing/default 플래그: precip_raw_was_null, humidity_raw_was_null, humidity_used_default_prior
- 라벨 provenance: label_source_point_count, target_rain_1h_mm, target_rain_3h_mm, label_source_name, label_rule_name
- 전처리 provenance: preprocessing_rule_name, data_version
- row drop 판단: is_model_input_ready

drop 요약
- train: audit {audit_metrics["train"]["audit_rows"]} rows, ready {audit_metrics["train"]["ready_rows"]}, dropped {audit_metrics["train"]["drop_rows"]} ({audit_metrics["train"]["drop_rate"]})
- valid: audit {audit_metrics["valid"]["audit_rows"]} rows, ready {audit_metrics["valid"]["ready_rows"]}, dropped {audit_metrics["valid"]["drop_rows"]} ({audit_metrics["valid"]["drop_rate"]})
- test: audit {audit_metrics["test"]["audit_rows"]} rows, ready {audit_metrics["test"]["ready_rows"]}, dropped {audit_metrics["test"]["drop_rows"]} ({audit_metrics["test"]["drop_rate"]})

stable district universe
- 총 24개 구
- 종로구 제외
- 순서: {districts}

중요 해석 포인트
- feature-only CSV 는 모델 입력용으로 축약된 결과물이므로 provenance 분석에는 부족합니다.
- drop 원인을 보려면 audit CSV 를 사용해야 합니다.
- label_rule_name, preprocessing_rule_name, data_version 이 모든 split 에서 고정값인지 반드시 확인해야 합니다.
- 현재 패키지 기준 라벨 원천은 std.seoul_aws_district_hourly 로 기록되어 있습니다.

추가 참고
- sql/021_heavyrain_modelready_aws_v5_1_final.sql
- sql/021_heavyrain_modelready_aws_v5_1_validation_gates.sql
- sql/021_heavyrain_modelready_aws_v5_1_diagnostics.sql
- reference/README.md
- reference/MODELING_HANDOFF.md
"""


def build_label_policy_text() -> str:
    return """v5.1 label policy

source of truth
- sql/021_heavyrain_modelready_aws_v5_1_final.sql
- data/train_audit.csv
- data/valid_audit.csv
- data/test_audit.csv

label column
- label

label meaning
- 미래 폭우 발생 여부를 나타내는 이진 타깃

fixed rule name
- 1h>=20 or 3h>=40 with lead 0..3

exact decision rule
- 현재 row 의 target_rain_1h_mm >= 20 이면 label = 1
- lead +1h row 의 target_rain_1h_mm >= 20 이면 label = 1
- lead +2h row 의 target_rain_1h_mm >= 20 이면 label = 1
- lead +3h row 의 target_rain_1h_mm >= 20 이면 label = 1
- 현재 row 의 target_rain_3h_mm >= 40 이면 label = 1
- lead +1h row 의 target_rain_3h_mm >= 40 이면 label = 1
- lead +2h row 의 target_rain_3h_mm >= 40 이면 label = 1
- lead +3h row 의 target_rain_3h_mm >= 40 이면 label = 1
- 위 조건이 모두 거짓이면 label = 0

label component columns available in audit
- target_rain_1h_mm
- target_rain_3h_mm
- label_source_point_count
- label_window_end
- label_ready_at
- label_source_name
- label_rule_name

label source note
- 현재 v5.1 final SQL 과 exported audit CSV 는 label_source_name 을 std.seoul_aws_district_hourly 로 기록합니다.
- 기존 상위 문서 일부에 서울시 강우량 기반 설명이 남아 있으므로, handoff 시에는 이 문서를 우선 기준으로 사용하십시오.

leakage warning
- target_rain_1h_mm, target_rain_3h_mm, label 은 audit 전용 컬럼이며 모델 입력에 직접 넣으면 안 됩니다.
"""


def build_split_policy_text(split_metrics: dict[str, dict[str, str]]) -> str:
    return f"""v5.1 split policy

source of truth
- sql/021_heavyrain_modelready_aws_v5_1_final.sql
- data/train_features_only.csv
- data/valid_features_only.csv
- data/test_features_only.csv

time-based split windows
- train: 2020-01-01 00:00:00+09 through 2023-12-31 23:00:00+09
- valid: 2024-01-01 00:00:00+09 through 2024-12-31 23:00:00+09
- test: 2025-01-01 00:00:00+09 through 2025-12-31 20:00:00+09

stable universe rule
- stable district universe is the intersection of districts present in train, valid, and test source periods
- result is 24 districts
- 종로구 is excluded

row counts from exported CSV
- train feature/model_input rows: {split_metrics["train"]["feature_rows"]}
- valid feature/model_input rows: {split_metrics["valid"]["feature_rows"]}
- test feature/model_input rows: {split_metrics["test"]["feature_rows"]}
- train label rows: {split_metrics["train"]["label_rows"]}
- valid label rows: {split_metrics["valid"]["label_rows"]}
- test label rows: {split_metrics["test"]["label_rows"]}

join rule
- join feature/model_input with label on district_name + base_datetime

pending note
- this package intentionally excludes pending rows
- handoff package is limited to labeled train/valid/test plus latest inference feature snapshot
"""


def build_district_universe_text(
    district_index_rows: list[dict[str, str]],
    grid_total_rows: int,
) -> str:
    lines = [
        "v5.1 stable district universe",
        "",
        "source of truth",
        "- data/train_features_only.csv",
        "- data/valid_features_only.csv",
        "- data/test_features_only.csv",
        "- metadata/district_index.csv",
        "",
        f"grid reference rows in data/seoul_district_grids.csv: {grid_total_rows}",
        f"stable modeling universe rows in v5.1 package: {len(district_index_rows)}",
        "",
        "exclusion rule",
        "- 종로구 is excluded from the v5.1 stable district universe",
        "",
        "district order and district_id",
    ]
    for row in district_index_rows:
        lines.append(f"- {row['district_id']}: {row['district_name']}")
    lines.append("")
    lines.append("note")
    lines.append("- data/seoul_district_grids.csv still contains 25 districts including 종로구 because it is a broader grid reference asset.")
    lines.append("- modeling and analysis for this package should follow metadata/district_index.csv, not the full 25-row grid file.")
    return "\n".join(lines) + "\n"


def build_preprocessing_spec_text() -> str:
    return """v5.1 preprocessing specification

source of truth
- sql/021_heavyrain_modelready_aws_v5_1_final.sql
- data/train_audit.csv
- data/valid_audit.csv
- data/test_audit.csv

fixed preprocessing rule name
- aws_hourly_precip0_humidity_locf_default65_v5_1

effective feature construction
1. base source table
- std.seoul_aws_district_hourly

2. stable district filter
- keep only districts that exist in train, valid, and test periods
- exclude 종로구

3. precipitation rule
- precip_mm_observed is the raw hourly precipitation
- if precip_mm_observed is null, set precip_mm_eff = 0
- precip_raw_was_null records whether this happened

4. humidity rule
- humidity_pct_observed is the raw hourly humidity
- if humidity_pct_observed is null, use last observation carried forward within district as humidity_locf_raw
- if both current humidity and locf value are unavailable, use default 65.0 as humidity_imputed_pct
- humidity_raw_was_null records whether raw humidity was null
- humidity_used_default_prior records whether fallback 65 was used

5. derived features
- dew_point_c is computed from temp_c and humidity_imputed_pct using Magnus formula
- past_rain_3h_mm = current precip_mm_eff + lag1 precip_mm_eff + lag2 precip_mm_eff
- temp_change_3h_c = temp_c - lag3 temp_c, using current value fallback if lag is missing
- humidity_change_3h_pct = humidity_imputed_pct - lag3 humidity_imputed_pct, using current value fallback if lag is missing
- moist_energy = temp_c * humidity_imputed_pct / 100

6. calendar features for model_input
- base_hour
- base_month
- day_of_week with Sunday = 0
- is_monsoon_season_flag where month 6..9 = 1
- hour_sin / hour_cos using 24-hour cycle
- month_sin / month_cos using 12-month cycle

7. model_input readiness gate
- a row is exported to feature-only and model_input only when:
  - temp_c is not null
  - dew_point_c is not null
  - past_rain_3h_mm is not null
  - temp_change_3h_c is not null
  - humidity_change_3h_pct is not null
  - moist_energy is not null
- this status is stored in is_model_input_ready

8. why feature-only is insufficient for direct handoff
- feature-only preserves only the final continuous weather variables
- it does not carry district_id
- it does not carry the calendar columns used by the final model_input contract
- handing off feature-only alone forces the receiver to re-implement temporal encoding, increasing train/serve mismatch risk

9. analysis note
- audit CSV is required to trace raw values, imputed values, default usage, label provenance, and row-drop reasons
"""


def build_validation_summary_text(
    district_index_rows: list[dict[str, str]],
    split_metrics: dict[str, dict[str, str]],
    audit_metrics: dict[str, dict[str, str]],
    feature_schema_match: bool,
    model_input_schema_match: bool,
    no_jongno: bool,
    key_alignment: dict[str, bool],
) -> str:
    all_gates_pass = (
        split_metrics["train"]["feature_months"] == "48"
        and split_metrics["valid"]["feature_months"] == "12"
        and split_metrics["test"]["feature_months"] == "12"
        and all(split_metrics[s]["feature_districts"] == "24" for s in ["train", "valid", "test"])
        and all(split_metrics[s]["feature_rows"] == split_metrics[s]["label_rows"] for s in ["train", "valid", "test"])
        and all(split_metrics[s]["feature_duplicate_key_groups"] == "0" for s in ["train", "valid", "test"])
        and all(key_alignment.values())
        and feature_schema_match
        and model_input_schema_match
        and no_jongno
        and len(district_index_rows) == 24
    )

    return f"""v5.1 validation summary

generated from
- exported CSV artifacts already present in data/trainset
- package build derivation for model_input
- reference SQL in sql/021_heavyrain_modelready_aws_v5_1_validation_gates.sql

high-level verdict
- MODEL_READY: {"YES" if all_gates_pass else "NO"}

gate-style summary
- train covers 48 months: {"PASS" if split_metrics["train"]["feature_months"] == "48" else "FAIL"}
- valid covers 12 months: {"PASS" if split_metrics["valid"]["feature_months"] == "12" else "FAIL"}
- test covers 12 months: {"PASS" if split_metrics["test"]["feature_months"] == "12" else "FAIL"}
- stable district universe count is 24: {"PASS" if len(district_index_rows) == 24 else "FAIL"}
- 종로구 excluded from split and inference exports: {"PASS" if no_jongno else "FAIL"}
- feature/label row counts match in every split: {"PASS" if all(split_metrics[s]["feature_rows"] == split_metrics[s]["label_rows"] for s in ["train", "valid", "test"]) else "FAIL"}
- feature/label join keys align in every split: {"PASS" if all(key_alignment.values()) else "FAIL"}
- no duplicate keys in feature exports: {"PASS" if all(split_metrics[s]["feature_duplicate_key_groups"] == "0" for s in ["train", "valid", "test"]) else "FAIL"}
- train feature-only schema equals inference feature-only schema: {"PASS" if feature_schema_match else "FAIL"}
- train model_input schema equals inference model_input schema: {"PASS" if model_input_schema_match else "FAIL"}
- inference latest row count is 24: {"PASS" if split_metrics["inference"]["feature_rows"] == "24" else "FAIL"}

split metrics
- train features={split_metrics["train"]["feature_rows"]}, labels={split_metrics["train"]["label_rows"]}, audit={audit_metrics["train"]["audit_rows"]}, positives={split_metrics["train"]["positive_rows"]} ({split_metrics["train"]["positive_rate"]}), dropped={audit_metrics["train"]["drop_rows"]} ({audit_metrics["train"]["drop_rate"]})
- valid features={split_metrics["valid"]["feature_rows"]}, labels={split_metrics["valid"]["label_rows"]}, audit={audit_metrics["valid"]["audit_rows"]}, positives={split_metrics["valid"]["positive_rows"]} ({split_metrics["valid"]["positive_rate"]}), dropped={audit_metrics["valid"]["drop_rows"]} ({audit_metrics["valid"]["drop_rate"]})
- test features={split_metrics["test"]["feature_rows"]}, labels={split_metrics["test"]["label_rows"]}, audit={audit_metrics["test"]["audit_rows"]}, positives={split_metrics["test"]["positive_rows"]} ({split_metrics["test"]["positive_rate"]}), dropped={audit_metrics["test"]["drop_rows"]} ({audit_metrics["test"]["drop_rate"]})

drop reason snapshot
- train: temp_c_null={audit_metrics["train"]["drop_temp_c_null"]}, dew_point_c_null={audit_metrics["train"]["drop_dew_point_c_null"]}, temp_change_3h_c_null={audit_metrics["train"]["drop_temp_change_3h_c_null"]}, humidity_change_3h_pct_null={audit_metrics["train"]["drop_humidity_change_3h_pct_null"]}, moist_energy_null={audit_metrics["train"]["drop_moist_energy_null"]}
- valid: temp_c_null={audit_metrics["valid"]["drop_temp_c_null"]}, dew_point_c_null={audit_metrics["valid"]["drop_dew_point_c_null"]}, temp_change_3h_c_null={audit_metrics["valid"]["drop_temp_change_3h_c_null"]}, humidity_change_3h_pct_null={audit_metrics["valid"]["drop_humidity_change_3h_pct_null"]}, moist_energy_null={audit_metrics["valid"]["drop_moist_energy_null"]}
- test: temp_c_null={audit_metrics["test"]["drop_temp_c_null"]}, dew_point_c_null={audit_metrics["test"]["drop_dew_point_c_null"]}, temp_change_3h_c_null={audit_metrics["test"]["drop_temp_change_3h_c_null"]}, humidity_change_3h_pct_null={audit_metrics["test"]["drop_humidity_change_3h_pct_null"]}, moist_energy_null={audit_metrics["test"]["drop_moist_energy_null"]}

policy checks
- label_source_name: {audit_metrics["train"]["label_source_name"]}
- label_rule_name: {audit_metrics["train"]["label_rule_name"]}
- preprocessing_rule_name: {audit_metrics["train"]["preprocessing_rule_name"]}
- data_version: {audit_metrics["train"]["data_version"]}

documentation risk that was corrected in this package
- existing top-level documents contain mixed statements about the label source
- this package resolves the ambiguity by following the actual v5.1 final SQL and exported audit CSV values
"""


def build_feature_label_mapping_rows() -> list[dict[str, str]]:
    rows = []
    for split in ["train", "valid", "test"]:
        rows.append(
            {
                "split": split,
                "feature_file": f"data/{split}_features_only.csv",
                "label_file": f"data/{split}_labels.csv",
                "join_key": "district_name + base_datetime",
                "notes": "Feature-only and label row counts are 1:1 aligned.",
            }
        )
        rows.append(
            {
                "split": split,
                "feature_file": f"data/{split}_model_input.csv",
                "label_file": f"data/{split}_labels.csv",
                "join_key": "district_name + base_datetime",
                "notes": "Recommended training join pair.",
            }
        )
    return rows


def write_manifest(path: Path, entries: list[ManifestEntry]) -> None:
    lines = [
        "FILE_MANIFEST",
        "",
        "Columns",
        "- file_path",
        "- role",
        "- source_path",
        "- generation_method",
        "- audience",
        "",
    ]
    for entry in entries:
        lines.append(f"file_path: {entry.file_path}")
        lines.append(f"role: {entry.role}")
        lines.append(f"source_path: {entry.source_path}")
        lines.append(f"generation_method: {entry.generation_method}")
        lines.append(f"audience: {entry.audience}")
        lines.append("")
    write_text(path, "\n".join(lines).rstrip() + "\n")


def main() -> None:
    args = parse_args()
    handoff_root = Path(args.handoff_dir).resolve()

    require_source_exports(from_db=args.from_db)
    verify_headers()

    if handoff_root.exists():
        if not args.overwrite:
            raise FileExistsError(
                f"{handoff_root} already exists. Re-run with --overwrite to rebuild it."
            )
        shutil.rmtree(handoff_root)

    handoff_root.mkdir(parents=True, exist_ok=True)
    manifest: list[ManifestEntry] = []

    data_dir = handoff_root / "data"
    metadata_dir = handoff_root / "metadata"
    sql_dir = handoff_root / "sql"
    scripts_dir = handoff_root / "scripts"
    reference_dir = handoff_root / "reference"
    for directory in [data_dir, metadata_dir, sql_dir, scripts_dir, reference_dir]:
        directory.mkdir(parents=True, exist_ok=True)

    district_index_rows = build_district_index()
    district_to_id = {
        row["district_name"]: row["district_id"] for row in district_index_rows
    }

    for package_name, source_path in SOURCE_DATA_FILES.items():
        copy_file(
            source_path,
            data_dir / package_name,
            manifest,
            role="existing_export_asset",
            audience="modeling_and_analysis",
        )

    for package_name, source_path in REFERENCE_FILES.items():
        copy_file(
            source_path,
            handoff_root / package_name,
            manifest,
            role="reference_document",
            audience="modeling_and_analysis",
        )

    for package_name, source_path in SQL_FILES.items():
        copy_file(
            source_path,
            handoff_root / package_name,
            manifest,
            role="reference_sql",
            audience="modeling_and_analysis",
        )

    for package_name, source_path in SCRIPT_FILES.items():
        copy_file(
            source_path,
            handoff_root / package_name,
            manifest,
            role="reference_export_script",
            audience="analysis_or_reexport",
        )

    model_input_headers: list[list[str]] = []
    split_model_input_rows = {}
    for split in ["train", "valid", "test"]:
        row_count, header = generate_model_input(
            SOURCE_DATA_FILES[f"{split}_features_only.csv"],
            data_dir / f"{split}_model_input.csv",
            district_to_id,
            manifest,
            role="generated_model_input",
            audience="modeling",
        )
        model_input_headers.append(header)
        split_model_input_rows[split] = row_count

    inference_model_rows, inference_model_header = generate_model_input(
        SOURCE_DATA_FILES["inference_features_latest.csv"],
        data_dir / "inference_model_input_latest.csv",
        district_to_id,
        manifest,
        role="generated_model_input",
        audience="modeling",
    )
    model_input_headers.append(inference_model_header)

    feature_schema_match = read_header(
        SOURCE_DATA_FILES["train_features_only.csv"]
    ) == read_header(SOURCE_DATA_FILES["inference_features_latest.csv"])
    model_input_schema_match = all(header == MODEL_INPUT_HEADER for header in model_input_headers)

    write_csv(
        metadata_dir / "district_index.csv",
        district_index_rows,
        ["district_id", "district_name"],
    )
    manifest.append(
        ManifestEntry(
            file_path="metadata/district_index.csv",
            role="district_mapping",
            source_path="generated from sorted distinct district_name in train/valid/test/inference exports",
            generation_method="newly_generated",
            audience="modeling_and_analysis",
        )
    )

    feature_dictionary_rows = build_feature_dictionary_rows()
    write_csv(
        metadata_dir / "feature_dictionary.csv",
        feature_dictionary_rows,
        [
            "column_name",
            "role",
            "dtype",
            "included_in_model_input",
            "recommended_for_numeric_matrix",
            "description",
            "notes",
        ],
    )
    manifest.append(
        ManifestEntry(
            file_path="metadata/feature_dictionary.csv",
            role="model_input_dictionary",
            source_path="generated from v5.1 final SQL and package model_input contract",
            generation_method="newly_generated",
            audience="modeling",
        )
    )

    audit_dictionary_rows = build_audit_dictionary_rows()
    write_csv(
        metadata_dir / "audit_dictionary.csv",
        audit_dictionary_rows,
        ["column_name", "category", "dtype", "analysis_use", "description", "notes"],
    )
    manifest.append(
        ManifestEntry(
            file_path="metadata/audit_dictionary.csv",
            role="audit_dictionary",
            source_path="generated from v5.1 final SQL and audit CSV schema",
            generation_method="newly_generated",
            audience="analysis",
        )
    )

    grid_rows = count_lines_minus_header(DISTRICT_GRID_FILE)

    feature_metrics = {
        "train": summarize_features(SOURCE_DATA_FILES["train_features_only.csv"]),
        "valid": summarize_features(SOURCE_DATA_FILES["valid_features_only.csv"]),
        "test": summarize_features(SOURCE_DATA_FILES["test_features_only.csv"]),
        "inference": summarize_features(SOURCE_DATA_FILES["inference_features_latest.csv"]),
    }
    label_metrics = {
        "train": summarize_labels(SOURCE_DATA_FILES["train_labels.csv"]),
        "valid": summarize_labels(SOURCE_DATA_FILES["valid_labels.csv"]),
        "test": summarize_labels(SOURCE_DATA_FILES["test_labels.csv"]),
    }
    audit_metrics_raw = {
        "train": summarize_audit(SOURCE_DATA_FILES["train_audit.csv"]),
        "valid": summarize_audit(SOURCE_DATA_FILES["valid_audit.csv"]),
        "test": summarize_audit(SOURCE_DATA_FILES["test_audit.csv"]),
    }

    split_metrics = {
        split: {
            "feature_rows": feature_metrics[split]["rows"],
            "feature_months": feature_metrics[split]["month_count"],
            "feature_districts": feature_metrics[split]["district_count"],
            "feature_duplicate_key_groups": feature_metrics[split]["duplicate_key_groups"],
            "label_rows": label_metrics[split]["rows"],
            "positive_rows": label_metrics[split]["positive_rows"],
            "positive_rate": label_metrics[split]["positive_rate"],
        }
        for split in ["train", "valid", "test"]
    }
    split_metrics["inference"] = {
        "feature_rows": feature_metrics["inference"]["rows"],
        "feature_months": feature_metrics["inference"]["month_count"],
        "feature_districts": feature_metrics["inference"]["district_count"],
        "feature_duplicate_key_groups": feature_metrics["inference"]["duplicate_key_groups"],
    }

    audit_metrics = {
        split: {
            "audit_rows": audit_metrics_raw[split]["rows"],
            "ready_rows": audit_metrics_raw[split]["ready_rows"],
            "drop_rows": audit_metrics_raw[split]["drop_rows"],
            "drop_rate": audit_metrics_raw[split]["drop_rate"],
            "label_rule_name": audit_metrics_raw[split]["label_rule_name"],
            "preprocessing_rule_name": audit_metrics_raw[split]["preprocessing_rule_name"],
            "data_version": audit_metrics_raw[split]["data_version"],
            "label_source_name": audit_metrics_raw[split]["label_source_name"],
            "drop_temp_c_null": audit_metrics_raw[split]["drop_temp_c_null"],
            "drop_dew_point_c_null": audit_metrics_raw[split]["drop_dew_point_c_null"],
            "drop_temp_change_3h_c_null": audit_metrics_raw[split]["drop_temp_change_3h_c_null"],
            "drop_humidity_change_3h_pct_null": audit_metrics_raw[split]["drop_humidity_change_3h_pct_null"],
            "drop_moist_energy_null": audit_metrics_raw[split]["drop_moist_energy_null"],
        }
        for split in ["train", "valid", "test"]
    }

    key_alignment = {
        split: compare_key_alignment(
            SOURCE_DATA_FILES[f"{split}_features_only.csv"],
            SOURCE_DATA_FILES[f"{split}_labels.csv"],
        )
        for split in ["train", "valid", "test"]
    }
    no_jongno = all("종로구" not in read_distinct_districts(SOURCE_DATA_FILES[key]) for key in [
        "train_features_only.csv",
        "valid_features_only.csv",
        "test_features_only.csv",
        "inference_features_latest.csv",
    ])

    class_balance_rows = []
    split_summary_rows = []
    drop_reason_rows = []
    for split in ["train", "valid", "test"]:
        class_balance_rows.append(
            {
                "split": split,
                "label_rows": split_metrics[split]["label_rows"],
                "positive_rows": split_metrics[split]["positive_rows"],
                "positive_rate": split_metrics[split]["positive_rate"],
            }
        )
        split_summary_rows.append(
            {
                "split": split,
                "feature_rows": split_metrics[split]["feature_rows"],
                "label_rows": split_metrics[split]["label_rows"],
                "audit_rows": audit_metrics[split]["audit_rows"],
                "ready_rows": audit_metrics[split]["ready_rows"],
                "drop_rows": audit_metrics[split]["drop_rows"],
                "drop_rate": audit_metrics[split]["drop_rate"],
                "district_count": split_metrics[split]["feature_districts"],
                "month_count": split_metrics[split]["feature_months"],
                "feature_label_key_alignment": "PASS" if key_alignment[split] else "FAIL",
            }
        )
        drop_reason_rows.append(
            {
                "split": split,
                "temp_c_null_rows": audit_metrics[split]["drop_temp_c_null"],
                "dew_point_c_null_rows": audit_metrics[split]["drop_dew_point_c_null"],
                "temp_change_3h_c_null_rows": audit_metrics[split]["drop_temp_change_3h_c_null"],
                "humidity_change_3h_pct_null_rows": audit_metrics[split]["drop_humidity_change_3h_pct_null"],
                "moist_energy_null_rows": audit_metrics[split]["drop_moist_energy_null"],
            }
        )

    write_csv(
        metadata_dir / "class_balance_summary.csv",
        class_balance_rows,
        ["split", "label_rows", "positive_rows", "positive_rate"],
    )
    manifest.append(
        ManifestEntry(
            file_path="metadata/class_balance_summary.csv",
            role="class_imbalance_summary",
            source_path="derived from train/valid/test label CSV",
            generation_method="newly_generated",
            audience="modeling",
        )
    )

    write_csv(
        metadata_dir / "split_summary.csv",
        split_summary_rows,
        [
            "split",
            "feature_rows",
            "label_rows",
            "audit_rows",
            "ready_rows",
            "drop_rows",
            "drop_rate",
            "district_count",
            "month_count",
            "feature_label_key_alignment",
        ],
    )
    manifest.append(
        ManifestEntry(
            file_path="metadata/split_summary.csv",
            role="split_summary",
            source_path="derived from feature/label/audit CSV counts",
            generation_method="newly_generated",
            audience="modeling_and_analysis",
        )
    )

    write_csv(
        metadata_dir / "drop_reason_summary.csv",
        drop_reason_rows,
        [
            "split",
            "temp_c_null_rows",
            "dew_point_c_null_rows",
            "temp_change_3h_c_null_rows",
            "humidity_change_3h_pct_null_rows",
            "moist_energy_null_rows",
        ],
    )
    manifest.append(
        ManifestEntry(
            file_path="metadata/drop_reason_summary.csv",
            role="drop_reason_summary",
            source_path="derived from train/valid/test audit CSV",
            generation_method="newly_generated",
            audience="analysis",
        )
    )

    write_csv(
        metadata_dir / "feature_label_join_map.csv",
        build_feature_label_mapping_rows(),
        ["split", "feature_file", "label_file", "join_key", "notes"],
    )
    manifest.append(
        ManifestEntry(
            file_path="metadata/feature_label_join_map.csv",
            role="join_contract",
            source_path="generated from package file contract",
            generation_method="newly_generated",
            audience="modeling_and_analysis",
        )
    )

    write_text(
        handoff_root / "README_FOR_MODELING.txt",
        build_readme_for_modeling(district_index_rows, split_metrics),
    )
    manifest.append(
        ManifestEntry(
            file_path="README_FOR_MODELING.txt",
            role="primary_modeling_readme",
            source_path="generated from package build script",
            generation_method="newly_generated",
            audience="modeling",
        )
    )

    write_text(
        handoff_root / "README_FOR_ANALYSIS.txt",
        build_readme_for_analysis(district_index_rows, audit_metrics),
    )
    manifest.append(
        ManifestEntry(
            file_path="README_FOR_ANALYSIS.txt",
            role="primary_analysis_readme",
            source_path="generated from package build script",
            generation_method="newly_generated",
            audience="analysis",
        )
    )

    text_docs = {
        "metadata/label_policy.txt": build_label_policy_text(),
        "metadata/split_policy.txt": build_split_policy_text(split_metrics),
        "metadata/district_universe.txt": build_district_universe_text(district_index_rows, grid_rows),
        "metadata/preprocessing_spec.txt": build_preprocessing_spec_text(),
        "metadata/validation_summary.txt": build_validation_summary_text(
            district_index_rows,
            split_metrics,
            audit_metrics,
            feature_schema_match,
            model_input_schema_match,
            no_jongno,
            key_alignment,
        ),
        "sql/export_model_input.sql": build_export_model_input_sql(),
        "sql/export_audit.sql": build_export_audit_sql(),
    }
    text_doc_roles = {
        "metadata/label_policy.txt": ("label_policy_document", "modeling_and_analysis"),
        "metadata/split_policy.txt": ("split_policy_document", "modeling_and_analysis"),
        "metadata/district_universe.txt": ("district_universe_document", "modeling_and_analysis"),
        "metadata/preprocessing_spec.txt": ("preprocessing_spec_document", "modeling_and_analysis"),
        "metadata/validation_summary.txt": ("validation_summary_document", "modeling_and_analysis"),
        "sql/export_model_input.sql": ("reexport_sql", "analysis_or_reexport"),
        "sql/export_audit.sql": ("reexport_sql", "analysis_or_reexport"),
    }
    for relative_path, content in text_docs.items():
        destination = handoff_root / relative_path
        write_text(destination, content)
        role, audience = text_doc_roles[relative_path]
        manifest.append(
            ManifestEntry(
                file_path=relative_path,
                role=role,
                source_path="generated from package build script",
                generation_method="newly_generated",
                audience=audience,
            )
        )

    source_mapping_rows = []
    for entry in manifest:
        source_mapping_rows.append(
            {
                "handoff_file": entry.file_path,
                "role": entry.role,
                "source_path": entry.source_path,
                "generation_method": entry.generation_method,
                "audience": entry.audience,
            }
        )
    write_csv(
        metadata_dir / "source_file_mapping.csv",
        source_mapping_rows,
        ["handoff_file", "role", "source_path", "generation_method", "audience"],
    )
    manifest.append(
        ManifestEntry(
            file_path="metadata/source_file_mapping.csv",
            role="source_mapping",
            source_path="generated from manifest entries",
            generation_method="newly_generated",
            audience="modeling_and_analysis",
        )
    )

    write_manifest(handoff_root / "FILE_MANIFEST.txt", manifest)

    print(f"handoff_root={handoff_root}")
    print(f"train_model_input_rows={split_model_input_rows['train']}")
    print(f"valid_model_input_rows={split_model_input_rows['valid']}")
    print(f"test_model_input_rows={split_model_input_rows['test']}")
    print(f"inference_model_input_rows={inference_model_rows}")


if __name__ == "__main__":
    main()
