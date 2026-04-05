from __future__ import annotations

from pathlib import Path

from core.db import get_conn


OUTPUT_DIR = Path(__file__).resolve().parent.parent / "data" / "trainset"

FEATURE_EXPORT_TARGETS = {
    "mart.hrain_v4_aws_train_features_20260402": OUTPUT_DIR / "seoul_train_features_only_v4_aws_20260402.csv",
    "mart.hrain_v4_aws_valid_features_20260402": OUTPUT_DIR / "seoul_valid_features_only_v4_aws_20260402.csv",
    "mart.hrain_v4_aws_test_features_20260402": OUTPUT_DIR / "seoul_test_features_only_v4_aws_20260402.csv",
}

LABEL_EXPORT_TARGETS = {
    "mart.hrain_v4_aws_train_labels_20260402": OUTPUT_DIR / "seoul_train_labels_v4_aws_20260402.csv",
    "mart.hrain_v4_aws_valid_labels_20260402": OUTPUT_DIR / "seoul_valid_labels_v4_aws_20260402.csv",
    "mart.hrain_v4_aws_test_labels_20260402": OUTPUT_DIR / "seoul_test_labels_v4_aws_20260402.csv",
}

AUDIT_EXPORT_TARGETS = {
    "mart.hrain_v4_aws_train_audit_20260402": OUTPUT_DIR / "seoul_train_audit_v4_aws_20260402.csv",
    "mart.hrain_v4_aws_valid_audit_20260402": OUTPUT_DIR / "seoul_valid_audit_v4_aws_20260402.csv",
    "mart.hrain_v4_aws_test_audit_20260402": OUTPUT_DIR / "seoul_test_audit_v4_aws_20260402.csv",
}

FEATURE_COLUMNS = """
district_name,
base_datetime,
temp_c,
precip_mm,
humidity_pct,
dew_point_c,
past_rain_3h_mm,
temp_change_3h_c,
humidity_change_3h_pct,
moist_energy
""".strip()

LABEL_COLUMNS = """
district_name,
base_datetime,
label
""".strip()

AUDIT_COLUMNS = """
product_type,
district_name,
base_datetime,
target_datetime,
lead_minutes,
precip_mm,
temp_c,
humidity_pct,
dew_point_c,
past_rain_3h_mm,
temp_change_3h_c,
humidity_change_3h_pct,
moist_energy,
label_window_end,
label_ready_at,
label_source_point_count,
target_rain_1h_mm,
target_rain_3h_mm,
label,
split_type,
label_source_name,
label_rule_name,
data_version
""".strip()


def export_table(table_name: str, columns: str, output_path: Path) -> None:
    copy_sql = f"""
    COPY (
        SELECT
            {columns}
        FROM {table_name}
        ORDER BY district_name, base_datetime
    ) TO STDOUT WITH CSV HEADER
    """
    with get_conn() as conn:
        with conn.cursor() as cur:
            with output_path.open("w", encoding="utf-8", newline="") as fp:
                cur.copy_expert(copy_sql, fp)


def export_group(targets: dict[str, Path], columns: str) -> None:
    for table_name, output_path in targets.items():
        export_table(table_name, columns, output_path)
        print(output_path)


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    export_group(FEATURE_EXPORT_TARGETS, FEATURE_COLUMNS)
    export_group(LABEL_EXPORT_TARGETS, LABEL_COLUMNS)
    export_group(AUDIT_EXPORT_TARGETS, AUDIT_COLUMNS)


if __name__ == "__main__":
    main()
