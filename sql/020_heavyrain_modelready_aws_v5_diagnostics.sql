SET search_path TO mart, std, public;

SELECT
    'A.source_minmax_std_seoul_aws_district_hourly' AS diagnostic_id,
    'std.seoul_aws_district_hourly'::TEXT AS source_table,
    MIN(observed_at) AS min_ts,
    MAX(observed_at) AS max_ts,
    COUNT(*) AS total_rows
FROM std.seoul_aws_district_hourly
WHERE district_name <> '종로구';

SELECT
    'A.source_district_count_std_seoul_aws_district_hourly' AS diagnostic_id,
    'std.seoul_aws_district_hourly'::TEXT AS source_table,
    COUNT(DISTINCT district_name) AS district_count
FROM std.seoul_aws_district_hourly
WHERE district_name <> '종로구';

SELECT
    'A.source_monthly_row_count_std_seoul_aws_district_hourly' AS diagnostic_id,
    'std.seoul_aws_district_hourly'::TEXT AS source_table,
    date_part('year', observed_at AT TIME ZONE 'Asia/Seoul')::INT AS year_n,
    date_part('month', observed_at AT TIME ZONE 'Asia/Seoul')::INT AS month_n,
    COUNT(*) AS row_count
FROM std.seoul_aws_district_hourly
WHERE district_name <> '종로구'
  AND observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
  AND observed_at <= TIMESTAMPTZ '2025-12-31 23:00:00+09'
GROUP BY
    diagnostic_id,
    source_table,
    year_n,
    month_n
ORDER BY year_n, month_n;

SELECT
    'A.source_district_row_count_std_seoul_aws_district_hourly' AS diagnostic_id,
    'std.seoul_aws_district_hourly'::TEXT AS source_table,
    district_name,
    COUNT(*) AS row_count
FROM std.seoul_aws_district_hourly
WHERE district_name <> '종로구'
  AND observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
  AND observed_at <= TIMESTAMPTZ '2025-12-31 23:00:00+09'
GROUP BY
    diagnostic_id,
    source_table,
    district_name
ORDER BY district_name;

SELECT
    'A.district_first_last_ts_std_seoul_aws_district_hourly' AS diagnostic_id,
    district_name,
    MIN(observed_at) AS first_ts,
    MAX(observed_at) AS last_ts
FROM std.seoul_aws_district_hourly
WHERE district_name <> '종로구'
GROUP BY
    diagnostic_id,
    district_name
ORDER BY district_name;

SELECT
    'A.district_year_row_count_std_seoul_aws_district_hourly' AS diagnostic_id,
    district_name,
    date_part('year', observed_at AT TIME ZONE 'Asia/Seoul')::INT AS year_n,
    COUNT(*) AS row_count
FROM std.seoul_aws_district_hourly
WHERE district_name <> '종로구'
  AND observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
  AND observed_at <= TIMESTAMPTZ '2025-12-31 23:00:00+09'
GROUP BY
    diagnostic_id,
    district_name,
    year_n
ORDER BY district_name, year_n;

SELECT
    'A.district_month_row_count_std_seoul_aws_district_hourly' AS diagnostic_id,
    district_name,
    to_char(observed_at AT TIME ZONE 'Asia/Seoul', 'YYYY-MM') AS year_month,
    COUNT(*) AS row_count
FROM std.seoul_aws_district_hourly
WHERE district_name <> '종로구'
  AND observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
  AND observed_at <= TIMESTAMPTZ '2025-12-31 23:00:00+09'
GROUP BY
    diagnostic_id,
    district_name,
    year_month
ORDER BY district_name, year_month;

SELECT
    'B.split_monthly_row_count_v5_features' AS diagnostic_id,
    'train'::TEXT AS split_name,
    to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM') AS year_month,
    COUNT(*) AS row_count
FROM mart.hrain_v5_aws_train_features_20260402
GROUP BY to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')
UNION ALL
SELECT
    'B.split_monthly_row_count_v5_features' AS diagnostic_id,
    'valid'::TEXT AS split_name,
    to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM') AS year_month,
    COUNT(*) AS row_count
FROM mart.hrain_v5_aws_valid_features_20260402
GROUP BY to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')
UNION ALL
SELECT
    'B.split_monthly_row_count_v5_features' AS diagnostic_id,
    'test'::TEXT AS split_name,
    to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM') AS year_month,
    COUNT(*) AS row_count
FROM mart.hrain_v5_aws_test_features_20260402
GROUP BY to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')
ORDER BY split_name, year_month;

SELECT
    'B.split_monthly_district_count_v5_features' AS diagnostic_id,
    'train'::TEXT AS split_name,
    to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM') AS year_month,
    COUNT(DISTINCT district_name) AS district_count
FROM mart.hrain_v5_aws_train_features_20260402
GROUP BY to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')
UNION ALL
SELECT
    'B.split_monthly_district_count_v5_features' AS diagnostic_id,
    'valid'::TEXT AS split_name,
    to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM') AS year_month,
    COUNT(DISTINCT district_name) AS district_count
FROM mart.hrain_v5_aws_valid_features_20260402
GROUP BY to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')
UNION ALL
SELECT
    'B.split_monthly_district_count_v5_features' AS diagnostic_id,
    'test'::TEXT AS split_name,
    to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM') AS year_month,
    COUNT(DISTINCT district_name) AS district_count
FROM mart.hrain_v5_aws_test_features_20260402
GROUP BY to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')
ORDER BY split_name, year_month;

SELECT
    'B.split_district_row_count_v5_features' AS diagnostic_id,
    'train'::TEXT AS split_name,
    district_name,
    COUNT(*) AS row_count
FROM mart.hrain_v5_aws_train_features_20260402
GROUP BY district_name
UNION ALL
SELECT
    'B.split_district_row_count_v5_features' AS diagnostic_id,
    'valid'::TEXT AS split_name,
    district_name,
    COUNT(*) AS row_count
FROM mart.hrain_v5_aws_valid_features_20260402
GROUP BY district_name
UNION ALL
SELECT
    'B.split_district_row_count_v5_features' AS diagnostic_id,
    'test'::TEXT AS split_name,
    district_name,
    COUNT(*) AS row_count
FROM mart.hrain_v5_aws_test_features_20260402
GROUP BY district_name
ORDER BY split_name, district_name;

WITH train_d AS (
    SELECT DISTINCT district_name
    FROM mart.hrain_v5_aws_train_features_20260402
),
valid_d AS (
    SELECT DISTINCT district_name
    FROM mart.hrain_v5_aws_valid_features_20260402
),
test_d AS (
    SELECT DISTINCT district_name
    FROM mart.hrain_v5_aws_test_features_20260402
)
SELECT
    'B.split_district_diff_v5_features' AS diagnostic_id,
    'train_minus_valid' AS diff_type,
    t.district_name
FROM train_d t
LEFT JOIN valid_d v
    ON v.district_name = t.district_name
WHERE v.district_name IS NULL
UNION ALL
SELECT
    'B.split_district_diff_v5_features' AS diagnostic_id,
    'train_minus_test' AS diff_type,
    t.district_name
FROM train_d t
LEFT JOIN test_d x
    ON x.district_name = t.district_name
WHERE x.district_name IS NULL
UNION ALL
SELECT
    'B.split_district_diff_v5_features' AS diagnostic_id,
    'valid_minus_train' AS diff_type,
    v.district_name
FROM valid_d v
LEFT JOIN train_d t
    ON t.district_name = v.district_name
WHERE t.district_name IS NULL
UNION ALL
SELECT
    'B.split_district_diff_v5_features' AS diagnostic_id,
    'test_minus_train' AS diff_type,
    x.district_name
FROM test_d x
LEFT JOIN train_d t
    ON t.district_name = x.district_name
WHERE t.district_name IS NULL
ORDER BY diff_type, district_name;

SELECT
    'B.jongno_row_count_v5_audit' AS diagnostic_id,
    'train'::TEXT AS split_name,
    COUNT(*) FILTER (WHERE district_name = '종로구') AS jongno_row_count
FROM mart.hrain_v5_aws_train_audit_20260402
UNION ALL
SELECT
    'B.jongno_row_count_v5_audit' AS diagnostic_id,
    'valid'::TEXT AS split_name,
    COUNT(*) FILTER (WHERE district_name = '종로구') AS jongno_row_count
FROM mart.hrain_v5_aws_valid_audit_20260402
UNION ALL
SELECT
    'B.jongno_row_count_v5_audit' AS diagnostic_id,
    'test'::TEXT AS split_name,
    COUNT(*) FILTER (WHERE district_name = '종로구') AS jongno_row_count
FROM mart.hrain_v5_aws_test_audit_20260402;

SELECT
    'B.final_district_universe_v5_stable_table' AS diagnostic_id,
    district_name
FROM mart.hrain_v5_aws_stable_districts_20260402
ORDER BY district_name;

SELECT
    'C.feature_null_diag_train' AS diagnostic_id,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE temp_c IS NULL) AS null_temp_c,
    COUNT(*) FILTER (WHERE precip_mm IS NULL) AS null_precip_mm,
    COUNT(*) FILTER (WHERE humidity_pct IS NULL) AS null_humidity_pct,
    COUNT(*) FILTER (WHERE dew_point_c IS NULL) AS null_dew_point_c,
    COUNT(*) FILTER (WHERE past_rain_3h_mm IS NULL) AS null_past_rain_3h_mm,
    COUNT(*) FILTER (WHERE temp_change_3h_c IS NULL) AS null_temp_change_3h_c,
    COUNT(*) FILTER (WHERE humidity_change_3h_pct IS NULL) AS null_humidity_change_3h_pct,
    COUNT(*) FILTER (WHERE moist_energy IS NULL) AS null_moist_energy
FROM mart.hrain_v5_aws_train_features_20260402;

SELECT
    'C.feature_null_ratio_by_district_train' AS diagnostic_id,
    district_name,
    COUNT(*) AS total_rows,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE dew_point_c IS NULL) / NULLIF(COUNT(*), 0),
        4
    ) AS pct_null_dew_point_c
FROM mart.hrain_v5_aws_train_features_20260402
GROUP BY district_name
ORDER BY pct_null_dew_point_c DESC NULLS LAST, district_name;

SELECT
    'C.feature_null_ratio_by_month_train' AS diagnostic_id,
    to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM') AS year_month,
    COUNT(*) AS total_rows,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE dew_point_c IS NULL) / NULLIF(COUNT(*), 0),
        4
    ) AS pct_null_dew_point_c
FROM mart.hrain_v5_aws_train_features_20260402
GROUP BY to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')
ORDER BY year_month;

SELECT
    'C.audit_imputation_flags_train' AS diagnostic_id,
    COUNT(*) AS audit_rows,
    COUNT(*) FILTER (WHERE humidity_raw_was_null) AS rows_humidity_raw_was_null,
    COUNT(*) FILTER (WHERE humidity_used_default_prior) AS rows_humidity_used_default_prior
FROM mart.hrain_v5_aws_train_audit_20260402;

SELECT
    'D.label_null_split_v5_audit' AS diagnostic_id,
    'train'::TEXT AS split_name,
    COUNT(*) FILTER (WHERE label = 0) AS label_0_count,
    COUNT(*) FILTER (WHERE label = 1) AS label_1_count,
    COUNT(*) FILTER (WHERE label IS NULL) AS label_null_count
FROM mart.hrain_v5_aws_train_audit_20260402
UNION ALL
SELECT
    'D.label_null_split_v5_audit' AS diagnostic_id,
    'valid'::TEXT AS split_name,
    COUNT(*) FILTER (WHERE label = 0) AS label_0_count,
    COUNT(*) FILTER (WHERE label = 1) AS label_1_count,
    COUNT(*) FILTER (WHERE label IS NULL) AS label_null_count
FROM mart.hrain_v5_aws_valid_audit_20260402
UNION ALL
SELECT
    'D.label_null_split_v5_audit' AS diagnostic_id,
    'test'::TEXT AS split_name,
    COUNT(*) FILTER (WHERE label = 0) AS label_0_count,
    COUNT(*) FILTER (WHERE label = 1) AS label_1_count,
    COUNT(*) FILTER (WHERE label IS NULL) AS label_null_count
FROM mart.hrain_v5_aws_test_audit_20260402;

SELECT
    'D.label_one_by_district_v5_features_join_labels' AS diagnostic_id,
    f.district_name,
    COUNT(*) FILTER (WHERE l.label = 1) AS label_1_count
FROM mart.hrain_v5_aws_train_features_20260402 f
INNER JOIN mart.hrain_v5_aws_train_labels_20260402 l
    ON l.district_name = f.district_name
   AND l.base_datetime = f.base_datetime
GROUP BY f.district_name
ORDER BY label_1_count ASC, f.district_name;

SELECT
    'D.label_one_by_month_train_v5_features_join_labels' AS diagnostic_id,
    to_char(f.base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM') AS year_month,
    COUNT(*) FILTER (WHERE l.label = 1) AS label_1_count
FROM mart.hrain_v5_aws_train_features_20260402 f
INNER JOIN mart.hrain_v5_aws_train_labels_20260402 l
    ON l.district_name = f.district_name
   AND l.base_datetime = f.base_datetime
GROUP BY to_char(f.base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')
ORDER BY year_month;

WITH base AS (
    SELECT
        a.district_name,
        a.observed_at,
        a.precip_mm
    FROM std.seoul_aws_district_hourly a
    INNER JOIN mart.hrain_v5_aws_stable_districts_20260402 s
        ON s.district_name = a.district_name
    WHERE a.observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
      AND a.observed_at <= TIMESTAMPTZ '2025-12-31 20:00:00+09'
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
        observed_at,
        CASE
            WHEN observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
             AND observed_at <= TIMESTAMPTZ '2023-12-31 23:00:00+09' THEN 'train'
            WHEN observed_at >= TIMESTAMPTZ '2024-01-01 00:00:00+09'
             AND observed_at <= TIMESTAMPTZ '2024-12-31 23:00:00+09' THEN 'valid'
            WHEN observed_at >= TIMESTAMPTZ '2025-01-01 00:00:00+09'
             AND observed_at <= TIMESTAMPTZ '2025-12-31 20:00:00+09' THEN 'test'
            ELSE NULL
        END AS split_type,
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
    'D.threshold_compare_by_split_on_aws_hourly_stable_universe' AS diagnostic_id,
    split_type,
    COUNT(*) AS row_count,
    SUM(label_20_40) AS positive_20_40,
    SUM(label_20_50) AS positive_20_50,
    ROUND(100.0 * SUM(label_20_40) / NULLIF(COUNT(*), 0), 6) AS prevalence_20_40,
    ROUND(100.0 * SUM(label_20_50) / NULLIF(COUNT(*), 0), 6) AS prevalence_20_50
FROM threshold_compare
WHERE split_type IS NOT NULL
GROUP BY split_type
ORDER BY split_type;

SELECT
    'D.label_future_row_coverage_v5_audit' AS diagnostic_id,
    split_type,
    COUNT(*) AS rows_total,
    COUNT(*) FILTER (WHERE label_source_point_count = 3) AS rows_full_future_3h,
    COUNT(*) FILTER (WHERE label_source_point_count < 3) AS rows_short_future_3h
FROM mart.hrain_v5_aws_snapshot_20260402
GROUP BY split_type
ORDER BY split_type;

SELECT
    'E.row_count_feature_minus_label_train' AS diagnostic_id,
    (
        SELECT COUNT(*)
        FROM mart.hrain_v5_aws_train_features_20260402 f
        LEFT JOIN mart.hrain_v5_aws_train_labels_20260402 l
            ON l.district_name = f.district_name
           AND l.base_datetime = f.base_datetime
        WHERE l.district_name IS NULL
    ) AS feature_rows_missing_label;

SELECT
    'E.row_count_label_minus_feature_train' AS diagnostic_id,
    (
        SELECT COUNT(*)
        FROM mart.hrain_v5_aws_train_labels_20260402 l
        LEFT JOIN mart.hrain_v5_aws_train_features_20260402 f
            ON f.district_name = l.district_name
           AND f.base_datetime = l.base_datetime
        WHERE f.district_name IS NULL
    ) AS label_rows_missing_feature;

SELECT
    'E.duplicate_key_train_features' AS diagnostic_id,
    COUNT(*) AS duplicate_key_groups
FROM (
    SELECT
        district_name,
        base_datetime
    FROM mart.hrain_v5_aws_train_features_20260402
    GROUP BY district_name, base_datetime
    HAVING COUNT(*) > 1
) d;

SELECT
    'E.feature_table_columns_information_schema' AS diagnostic_id,
    table_name,
    STRING_AGG(column_name, ', ' ORDER BY ordinal_position) AS column_list
FROM information_schema.columns
WHERE table_schema = 'mart'
  AND table_name IN (
      'hrain_v5_aws_train_features_20260402',
      'hrain_v5_aws_valid_features_20260402',
      'hrain_v5_aws_test_features_20260402'
  )
GROUP BY table_name
ORDER BY table_name;

SELECT
    'E.leakage_column_hits_in_feature_tables' AS diagnostic_id,
    table_name,
    COUNT(*) FILTER (
        WHERE column_name IN (
            'target_rain_1h_mm',
            'target_rain_3h_mm',
            'label_source_point_count',
            'label_window_end',
            'label_ready_at',
            'label',
            'split_type',
            'data_version',
            'product_type',
            'target_datetime',
            'lead_minutes'
        )
    ) AS leakage_or_audit_column_hits
FROM information_schema.columns
WHERE table_schema = 'mart'
  AND table_name IN (
      'hrain_v5_aws_train_features_20260402',
      'hrain_v5_aws_valid_features_20260402',
      'hrain_v5_aws_test_features_20260402'
  )
GROUP BY table_name
ORDER BY table_name;


