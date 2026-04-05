-- A. 기간 커버리지 진단
SELECT
    'std.seoul_aws_district_hourly' AS source_table,
    MIN(observed_at) AS min_ts,
    MAX(observed_at) AS max_ts,
    COUNT(*) AS total_rows
FROM std.seoul_aws_district_hourly
WHERE district_name <> '종로구';

SELECT
    date_part('year', observed_at)::INT AS year,
    date_part('month', observed_at)::INT AS month,
    COUNT(*) AS row_count
FROM std.seoul_aws_district_hourly
WHERE district_name <> '종로구'
GROUP BY 1, 2
ORDER BY 1, 2;

SELECT
    'train' AS split_name,
    to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM') AS year_month,
    COUNT(*) AS row_count
FROM mart.hrain_v4_aws_train_audit_20260402
GROUP BY 1, 2
UNION ALL
SELECT
    'valid' AS split_name,
    to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM') AS year_month,
    COUNT(*) AS row_count
FROM mart.hrain_v4_aws_valid_audit_20260402
GROUP BY 1, 2
UNION ALL
SELECT
    'test' AS split_name,
    to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM') AS year_month,
    COUNT(*) AS row_count
FROM mart.hrain_v4_aws_test_audit_20260402
GROUP BY 1, 2
ORDER BY split_name, year_month;

-- B. district universe 진단
SELECT
    COUNT(DISTINCT district_name) AS source_district_count,
    STRING_AGG(DISTINCT district_name, ', ' ORDER BY district_name) AS source_districts
FROM std.seoul_aws_district_hourly
WHERE district_name <> '종로구';

SELECT
    'train' AS split_name,
    COUNT(DISTINCT district_name) AS district_count,
    STRING_AGG(DISTINCT district_name, ', ' ORDER BY district_name) AS districts
FROM mart.hrain_v4_aws_train_audit_20260402
UNION ALL
SELECT
    'valid' AS split_name,
    COUNT(DISTINCT district_name) AS district_count,
    STRING_AGG(DISTINCT district_name, ', ' ORDER BY district_name) AS districts
FROM mart.hrain_v4_aws_valid_audit_20260402
UNION ALL
SELECT
    'test' AS split_name,
    COUNT(DISTINCT district_name) AS district_count,
    STRING_AGG(DISTINCT district_name, ', ' ORDER BY district_name) AS districts
FROM mart.hrain_v4_aws_test_audit_20260402;

WITH train_d AS (
    SELECT DISTINCT district_name
    FROM mart.hrain_v4_aws_train_audit_20260402
),
valid_d AS (
    SELECT DISTINCT district_name
    FROM mart.hrain_v4_aws_valid_audit_20260402
),
test_d AS (
    SELECT DISTINCT district_name
    FROM mart.hrain_v4_aws_test_audit_20260402
)
SELECT
    'train_not_valid' AS diff_type,
    t.district_name
FROM train_d t
LEFT JOIN valid_d v
    ON v.district_name = t.district_name
WHERE v.district_name IS NULL
UNION ALL
SELECT
    'train_not_test' AS diff_type,
    t.district_name
FROM train_d t
LEFT JOIN test_d x
    ON x.district_name = t.district_name
WHERE x.district_name IS NULL
UNION ALL
SELECT
    'valid_not_train' AS diff_type,
    v.district_name
FROM valid_d v
LEFT JOIN train_d t
    ON t.district_name = v.district_name
WHERE t.district_name IS NULL
UNION ALL
SELECT
    'test_not_train' AS diff_type,
    x.district_name
FROM test_d x
LEFT JOIN train_d t
    ON t.district_name = x.district_name
WHERE t.district_name IS NULL
ORDER BY diff_type, district_name;

SELECT
    'train' AS split_name,
    COUNT(*) FILTER (WHERE district_name = '종로구') AS jongno_rows
FROM mart.hrain_v4_aws_train_audit_20260402
UNION ALL
SELECT
    'valid' AS split_name,
    COUNT(*) FILTER (WHERE district_name = '종로구') AS jongno_rows
FROM mart.hrain_v4_aws_valid_audit_20260402
UNION ALL
SELECT
    'test' AS split_name,
    COUNT(*) FILTER (WHERE district_name = '종로구') AS jongno_rows
FROM mart.hrain_v4_aws_test_audit_20260402;

-- C. label 분포 진단
SELECT
    'train' AS split_name,
    COUNT(*) FILTER (WHERE label = 0) AS label_0_count,
    COUNT(*) FILTER (WHERE label = 1) AS label_1_count,
    COUNT(*) FILTER (WHERE label IS NULL) AS label_null_count
FROM mart.hrain_v4_aws_train_audit_20260402
UNION ALL
SELECT
    'valid' AS split_name,
    COUNT(*) FILTER (WHERE label = 0) AS label_0_count,
    COUNT(*) FILTER (WHERE label = 1) AS label_1_count,
    COUNT(*) FILTER (WHERE label IS NULL) AS label_null_count
FROM mart.hrain_v4_aws_valid_audit_20260402
UNION ALL
SELECT
    'test' AS split_name,
    COUNT(*) FILTER (WHERE label = 0) AS label_0_count,
    COUNT(*) FILTER (WHERE label = 1) AS label_1_count,
    COUNT(*) FILTER (WHERE label IS NULL) AS label_null_count
FROM mart.hrain_v4_aws_test_audit_20260402;

SELECT
    district_name,
    COUNT(*) FILTER (WHERE label = 1) AS label_1_count
FROM mart.hrain_v4_aws_snapshot_20260402
GROUP BY district_name
ORDER BY label_1_count DESC, district_name;

SELECT
    split_type,
    to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM') AS year_month,
    COUNT(*) FILTER (WHERE label = 1) AS label_1_count
FROM mart.hrain_v4_aws_snapshot_20260402
GROUP BY split_type, year_month
ORDER BY split_type, year_month;

WITH base AS (
    SELECT
        district_name,
        observed_at,
        precip_mm
    FROM std.seoul_aws_district_hourly
    WHERE district_name <> '종로구'
      AND observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
      AND observed_at <= TIMESTAMPTZ '2025-12-31 20:00:00+09'
),
forward_calc AS (
    SELECT
        district_name,
        observed_at,
        precip_mm,
        SUM(COALESCE(precip_mm, 0.0)) OVER (
            PARTITION BY district_name
            ORDER BY observed_at
            ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING
        ) AS forward_rain_3h_mm
    FROM base
),
threshold_compare AS (
    SELECT
        district_name,
        observed_at,
        CASE
            WHEN COALESCE(precip_mm, 0.0) >= 20.0
              OR COALESCE(LEAD(precip_mm, 1) OVER w, 0.0) >= 20.0
              OR COALESCE(LEAD(precip_mm, 2) OVER w, 0.0) >= 20.0
              OR COALESCE(LEAD(precip_mm, 3) OVER w, 0.0) >= 20.0
              OR COALESCE(forward_rain_3h_mm, 0.0) >= 40.0
              OR COALESCE(LEAD(forward_rain_3h_mm, 1) OVER w, 0.0) >= 40.0
              OR COALESCE(LEAD(forward_rain_3h_mm, 2) OVER w, 0.0) >= 40.0
              OR COALESCE(LEAD(forward_rain_3h_mm, 3) OVER w, 0.0) >= 40.0
            THEN 1
            ELSE 0
        END AS label_20_40,
        CASE
            WHEN COALESCE(precip_mm, 0.0) >= 20.0
              OR COALESCE(LEAD(precip_mm, 1) OVER w, 0.0) >= 20.0
              OR COALESCE(LEAD(precip_mm, 2) OVER w, 0.0) >= 20.0
              OR COALESCE(LEAD(precip_mm, 3) OVER w, 0.0) >= 20.0
              OR COALESCE(forward_rain_3h_mm, 0.0) >= 50.0
              OR COALESCE(LEAD(forward_rain_3h_mm, 1) OVER w, 0.0) >= 50.0
              OR COALESCE(LEAD(forward_rain_3h_mm, 2) OVER w, 0.0) >= 50.0
              OR COALESCE(LEAD(forward_rain_3h_mm, 3) OVER w, 0.0) >= 50.0
            THEN 1
            ELSE 0
        END AS label_20_50
    FROM forward_calc
    WINDOW w AS (PARTITION BY district_name ORDER BY observed_at)
)
SELECT
    COUNT(*) FILTER (WHERE label_20_40 = 1) AS positive_20_40,
    COUNT(*) FILTER (WHERE label_20_50 = 1) AS positive_20_50
FROM threshold_compare;

WITH rain_base AS (
    SELECT
        district_name,
        base_datetime
    FROM mart.seoul_district_ultra_now
    WHERE base_datetime >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
      AND base_datetime <= TIMESTAMPTZ '2025-12-31 20:00:00+09'
),
rain_join AS (
    SELECT
        b.district_name,
        b.base_datetime,
        x.target_rain_1h_mm,
        x.target_rain_3h_mm
    FROM rain_base b
    LEFT JOIN LATERAL (
        SELECT
            CASE
                WHEN COUNT(r.observed_at) FILTER (
                    WHERE r.observed_at <= b.base_datetime + INTERVAL '1 hour'
                ) = 0 THEN NULL
                ELSE ROUND(
                    SUM(COALESCE(r.max_rain_10m_mm, 0.0)) FILTER (
                        WHERE r.observed_at <= b.base_datetime + INTERVAL '1 hour'
                    )::NUMERIC,
                    3
                )::DOUBLE PRECISION
            END AS target_rain_1h_mm,
            CASE
                WHEN COUNT(r.observed_at) = 0 THEN NULL
                ELSE ROUND(SUM(COALESCE(r.max_rain_10m_mm, 0.0))::NUMERIC, 3)::DOUBLE PRECISION
            END AS target_rain_3h_mm
        FROM mart.seoul_rainfall_district_latest r
        WHERE r.district_name = b.district_name
          AND r.observed_at > b.base_datetime
          AND r.observed_at <= b.base_datetime + INTERVAL '3 hours'
    ) x ON TRUE
),
aws_base AS (
    SELECT
        district_name,
        observed_at AS base_datetime,
        precip_mm
    FROM std.seoul_aws_district_hourly
    WHERE district_name <> '종로구'
      AND observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
      AND observed_at <= TIMESTAMPTZ '2025-12-31 20:00:00+09'
),
aws_forward AS (
    SELECT
        district_name,
        base_datetime,
        precip_mm,
        SUM(COALESCE(precip_mm, 0.0)) OVER (
            PARTITION BY district_name
            ORDER BY base_datetime
            ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING
        ) AS target_rain_3h_mm
    FROM aws_base
),
aws_label AS (
    SELECT
        district_name,
        base_datetime,
        COALESCE(LEAD(precip_mm, 1) OVER w, 0.0) AS target_rain_1h_mm,
        target_rain_3h_mm
    FROM aws_forward
    WINDOW w AS (PARTITION BY district_name ORDER BY base_datetime)
)
SELECT
    'mart.seoul_rainfall_district_latest' AS source_name,
    COUNT(*) FILTER (WHERE target_rain_3h_mm IS NOT NULL) AS target_rain_3h_non_null_rows
FROM rain_join
UNION ALL
SELECT
    'std.seoul_aws_district_hourly' AS source_name,
    COUNT(*) FILTER (WHERE target_rain_3h_mm IS NOT NULL) AS target_rain_3h_non_null_rows
FROM aws_label;

-- D. leakage 컬럼 진단
SELECT
    column_name,
    role_category,
    include_in_model_feature_csv,
    include_in_label_csv,
    include_in_audit_csv
FROM (
    VALUES
        ('district_name', 'metadata', FALSE, TRUE, TRUE),
        ('base_datetime', 'metadata', FALSE, TRUE, TRUE),
        ('temp_c', 'feature', TRUE, FALSE, TRUE),
        ('precip_mm', 'feature', TRUE, FALSE, TRUE),
        ('humidity_pct', 'feature', TRUE, FALSE, TRUE),
        ('dew_point_c', 'feature', TRUE, FALSE, TRUE),
        ('past_rain_3h_mm', 'feature', TRUE, FALSE, TRUE),
        ('temp_change_3h_c', 'feature', TRUE, FALSE, TRUE),
        ('humidity_change_3h_pct', 'feature', TRUE, FALSE, TRUE),
        ('moist_energy', 'feature', TRUE, FALSE, TRUE),
        ('label', 'target', FALSE, TRUE, TRUE),
        ('target_rain_1h_mm', 'leakage_risk', FALSE, FALSE, TRUE),
        ('target_rain_3h_mm', 'leakage_risk', FALSE, FALSE, TRUE),
        ('label_source_point_count', 'leakage_risk', FALSE, FALSE, TRUE),
        ('label_window_end', 'leakage_risk', FALSE, FALSE, TRUE),
        ('label_ready_at', 'leakage_risk', FALSE, FALSE, TRUE),
        ('split_type', 'metadata', FALSE, FALSE, TRUE),
        ('label_source_name', 'metadata', FALSE, FALSE, TRUE),
        ('label_rule_name', 'metadata', FALSE, FALSE, TRUE),
        ('data_version', 'metadata', FALSE, FALSE, TRUE)
) AS x(column_name, role_category, include_in_model_feature_csv, include_in_label_csv, include_in_audit_csv)
ORDER BY column_name;

SELECT
    table_name,
    STRING_AGG(column_name, ', ' ORDER BY ordinal_position) AS column_list
FROM information_schema.columns
WHERE table_schema = 'mart'
  AND table_name IN (
      'hrain_v4_aws_train_features_20260402',
      'hrain_v4_aws_valid_features_20260402',
      'hrain_v4_aws_test_features_20260402',
      'hrain_v4_aws_train_labels_20260402',
      'hrain_v4_aws_valid_labels_20260402',
      'hrain_v4_aws_test_labels_20260402'
  )
GROUP BY table_name
ORDER BY table_name;

SELECT
    table_name,
    COUNT(*) FILTER (
        WHERE column_name IN (
            'target_rain_1h_mm',
            'target_rain_3h_mm',
            'label_source_point_count',
            'label_window_end',
            'label_ready_at',
            'dataset_status',
            'is_trainable',
            'split_type',
            'data_version'
        )
    ) AS leakage_column_count
FROM information_schema.columns
WHERE table_schema = 'mart'
  AND table_name IN (
      'hrain_v4_aws_train_features_20260402',
      'hrain_v4_aws_valid_features_20260402',
      'hrain_v4_aws_test_features_20260402'
  )
GROUP BY table_name
ORDER BY table_name;
