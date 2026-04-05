SELECT
    'train' AS split_name,
    COUNT(*) AS row_count
FROM mart.seoul_district_heavyrain_train_corr_v3_aws_20260401
UNION ALL
SELECT
    'valid' AS split_name,
    COUNT(*) AS row_count
FROM mart.seoul_district_heavyrain_valid_corr_v3_aws_20260401
UNION ALL
SELECT
    'test' AS split_name,
    COUNT(*) AS row_count
FROM mart.seoul_district_heavyrain_test_corr_v3_aws_20260401
ORDER BY split_name;

SELECT
    split_type,
    COUNT(*) FILTER (WHERE target_rain_1h_mm IS NOT NULL) AS target_rain_1h_non_null_count,
    COUNT(*) FILTER (WHERE target_rain_3h_mm IS NOT NULL) AS target_rain_3h_non_null_count,
    COUNT(*) FILTER (WHERE label IS NOT NULL) AS label_non_null_count
FROM mart.seoul_district_heavyrain_snapshot_corr_v3_aws_20260401
GROUP BY split_type
ORDER BY split_type;

SELECT
    split_type,
    label,
    COUNT(*) AS row_count
FROM mart.seoul_district_heavyrain_snapshot_corr_v3_aws_20260401
GROUP BY split_type, label
ORDER BY split_type, label;

SELECT
    'std.seoul_aws_district_hourly' AS source_table,
    COUNT(*) AS total_rows,
    MIN(observed_at) AS min_ts,
    MAX(observed_at) AS max_ts,
    COUNT(DISTINCT district_name) AS distinct_district_count,
    COUNT(*) FILTER (
        WHERE observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
          AND observed_at <= TIMESTAMPTZ '2025-12-31 23:59:59+09'
    ) AS rows_2020_2025
FROM std.seoul_aws_district_hourly;

SELECT
    base_datetime,
    district_name,
    target_rain_1h_mm,
    target_rain_3h_mm,
    label
FROM mart.seoul_district_heavyrain_snapshot_corr_v3_aws_20260401
WHERE label IN (0, 1)
ORDER BY district_name, base_datetime
LIMIT 10;
