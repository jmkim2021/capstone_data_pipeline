from __future__ import annotations

from pathlib import Path

from core.db import get_conn


OUTPUT_DIR = Path(__file__).resolve().parent.parent / "data" / "trainset"

EXPORT_TARGETS = {
    "mart.seoul_district_heavyrain_train_fixed_v2_20260401": OUTPUT_DIR / "seoul_train_mart_v2_fixed_20260401.csv",
    "mart.seoul_district_heavyrain_valid_fixed_v2_20260401": OUTPUT_DIR / "seoul_valid_mart_v2_fixed_20260401.csv",
    "mart.seoul_district_heavyrain_test_fixed_v2_20260401": OUTPUT_DIR / "seoul_test_mart_v2_fixed_20260401.csv",
}

COLUMN_LIST = """
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
dataset_status,
is_trainable,
split_type,
data_version
""".strip()


def export_table(table_name: str, output_path: Path) -> None:
    copy_sql = f"""
    COPY (
        SELECT
            {COLUMN_LIST}
        FROM {table_name}
        ORDER BY district_name, base_datetime
    ) TO STDOUT WITH CSV HEADER
    """
    with get_conn() as conn:
        with conn.cursor() as cur:
            with output_path.open("w", encoding="utf-8", newline="") as fp:
                cur.copy_expert(copy_sql, fp)


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for table_name, output_path in EXPORT_TARGETS.items():
        export_table(table_name, output_path)
        print(output_path)


if __name__ == "__main__":
    main()
