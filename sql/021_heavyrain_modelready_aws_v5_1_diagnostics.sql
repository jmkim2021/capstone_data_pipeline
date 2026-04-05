SET search_path TO mart, std, public;

DROP TABLE IF EXISTS temp_hrain_v5_1_threshold_compare;

CREATE TEMP TABLE temp_hrain_v5_1_threshold_compare AS
WITH base AS (
    SELECT
        a.district_name,
        a.observed_at,
        a.precip_mm
    FROM std.seoul_aws_district_hourly a
    INNER JOIN mart.hrain_v5_1_aws_stable_districts_20260402 s
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
)
SELECT
    district_name,
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
WINDOW w AS (PARTITION BY district_name ORDER BY observed_at);

SELECT
    'A1_label_policy_compare_by_split' AS diagnostic_id,
    split_type,
    COUNT(*) AS row_count,
    SUM(label_20_40) AS positive_20_40,
    ROUND(100.0 * SUM(label_20_40) / NULLIF(COUNT(*), 0), 4) AS positive_rate_20_40_pct,
    SUM(label_20_50) AS positive_20_50,
    ROUND(100.0 * SUM(label_20_50) / NULLIF(COUNT(*), 0), 4) AS positive_rate_20_50_pct
FROM temp_hrain_v5_1_threshold_compare
WHERE split_type IS NOT NULL
GROUP BY split_type
ORDER BY split_type;

SELECT
    'A2_label_policy_compare_by_district_train' AS diagnostic_id,
    district_name,
    COUNT(*) FILTER (WHERE split_type = 'train' AND label_20_40 = 1) AS positive_20_40_train,
    COUNT(*) FILTER (WHERE split_type = 'train' AND label_20_50 = 1) AS positive_20_50_train
FROM temp_hrain_v5_1_threshold_compare
GROUP BY district_name
ORDER BY district_name;

SELECT
    'A3_label_policy_compare_by_month_train' AS diagnostic_id,
    to_char(observed_at AT TIME ZONE 'Asia/Seoul', 'YYYY-MM') AS year_month,
    COUNT(*) FILTER (WHERE split_type = 'train' AND label_20_40 = 1) AS positive_20_40_train,
    COUNT(*) FILTER (WHERE split_type = 'train' AND label_20_50 = 1) AS positive_20_50_train
FROM temp_hrain_v5_1_threshold_compare
WHERE split_type = 'train'
GROUP BY to_char(observed_at AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')
ORDER BY year_month;

SELECT
    'B1_preprocessing_counts_feature_base' AS diagnostic_id,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE humidity_raw_was_null) AS humidity_raw_null_rows,
    COUNT(*) FILTER (WHERE humidity_used_default_prior) AS humidity_default65_rows,
    COUNT(*) FILTER (WHERE precip_raw_was_null) AS precip_replaced_with_zero_rows,
    COUNT(*) FILTER (WHERE is_model_input_ready) AS model_input_ready_rows,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_model_input_ready) / NULLIF(COUNT(*), 0), 4) AS model_input_ready_pct
FROM mart.hrain_v5_1_aws_feature_base_20260402;

SELECT
    'B2_inference_source_minimum_columns_exist' AS diagnostic_id,
    COUNT(*) FILTER (WHERE column_name = 'district_name') AS has_district_name,
    COUNT(*) FILTER (WHERE column_name = 'observed_at') AS has_observed_at,
    COUNT(*) FILTER (WHERE column_name = 'temp_c') AS has_temp_c,
    COUNT(*) FILTER (WHERE column_name = 'precip_mm') AS has_precip_mm,
    COUNT(*) FILTER (WHERE column_name = 'humidity_pct') AS has_humidity_pct
FROM information_schema.columns
WHERE table_schema = 'std'
  AND table_name = 'seoul_aws_district_hourly';

SELECT
    'B3_inference_latest_row_count' AS diagnostic_id,
    COUNT(*) AS inference_latest_rows,
    COUNT(DISTINCT district_name) AS inference_latest_districts
FROM mart.hrain_v5_1_aws_inference_features_latest_20260402;

SELECT
    'B4_train_vs_inference_feature_schema' AS diagnostic_id,
    a.column_name
FROM information_schema.columns a
LEFT JOIN information_schema.columns b
    ON b.table_schema = 'mart'
   AND b.table_name = 'hrain_v5_1_aws_inference_features_latest_20260402'
   AND b.column_name = a.column_name
WHERE a.table_schema = 'mart'
  AND a.table_name = 'hrain_v5_1_aws_train_features_20260402'
  AND b.column_name IS NULL
ORDER BY a.ordinal_position;

SELECT
    'C1_split_monthly_row_count_features' AS diagnostic_id,
    'train'::TEXT AS split_name,
    to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM') AS year_month,
    COUNT(*) AS row_count
FROM mart.hrain_v5_1_aws_train_features_20260402
GROUP BY to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')
UNION ALL
SELECT
    'C1_split_monthly_row_count_features',
    'valid'::TEXT,
    to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM'),
    COUNT(*)
FROM mart.hrain_v5_1_aws_valid_features_20260402
GROUP BY to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')
UNION ALL
SELECT
    'C1_split_monthly_row_count_features',
    'test'::TEXT,
    to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM'),
    COUNT(*)
FROM mart.hrain_v5_1_aws_test_features_20260402
GROUP BY to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')
ORDER BY split_name, year_month;

SELECT
    'C2_split_monthly_district_count_features' AS diagnostic_id,
    'train'::TEXT AS split_name,
    to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM') AS year_month,
    COUNT(DISTINCT district_name) AS district_count
FROM mart.hrain_v5_1_aws_train_features_20260402
GROUP BY to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')
UNION ALL
SELECT
    'C2_split_monthly_district_count_features',
    'valid'::TEXT,
    to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM'),
    COUNT(DISTINCT district_name)
FROM mart.hrain_v5_1_aws_valid_features_20260402
GROUP BY to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')
UNION ALL
SELECT
    'C2_split_monthly_district_count_features',
    'test'::TEXT,
    to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM'),
    COUNT(DISTINCT district_name)
FROM mart.hrain_v5_1_aws_test_features_20260402
GROUP BY to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')
ORDER BY split_name, year_month;

SELECT
    'C3_split_drop_summary' AS diagnostic_id,
    split_name,
    audit_rows,
    feature_rows,
    dropped_rows,
    ROUND(100.0 * dropped_rows / NULLIF(audit_rows, 0), 4) AS drop_rate_pct
FROM (
    SELECT
        'train'::TEXT AS split_name,
        (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_train_audit_20260402) AS audit_rows,
        (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_train_features_20260402) AS feature_rows,
        (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_train_audit_20260402) - (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_train_features_20260402) AS dropped_rows
    UNION ALL
    SELECT
        'valid'::TEXT,
        (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_valid_audit_20260402),
        (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_valid_features_20260402),
        (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_valid_audit_20260402) - (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_valid_features_20260402)
    UNION ALL
    SELECT
        'test'::TEXT,
        (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_test_audit_20260402),
        (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_test_features_20260402),
        (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_test_audit_20260402) - (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_test_features_20260402)
) q
ORDER BY split_name;

SELECT
    'C4_drop_reason_by_split' AS diagnostic_id,
    'train'::TEXT AS split_name,
    COUNT(*) FILTER (WHERE temp_c IS NULL) AS temp_c_null_rows,
    COUNT(*) FILTER (WHERE dew_point_c IS NULL) AS dew_point_null_rows,
    COUNT(*) FILTER (WHERE temp_change_3h_c IS NULL) AS temp_change_null_rows,
    COUNT(*) FILTER (WHERE humidity_change_3h_pct IS NULL) AS humidity_change_null_rows,
    COUNT(*) FILTER (WHERE moist_energy IS NULL) AS moist_energy_null_rows
FROM mart.hrain_v5_1_aws_train_audit_20260402
UNION ALL
SELECT
    'C4_drop_reason_by_split',
    'valid'::TEXT,
    COUNT(*) FILTER (WHERE temp_c IS NULL),
    COUNT(*) FILTER (WHERE dew_point_c IS NULL),
    COUNT(*) FILTER (WHERE temp_change_3h_c IS NULL),
    COUNT(*) FILTER (WHERE humidity_change_3h_pct IS NULL),
    COUNT(*) FILTER (WHERE moist_energy IS NULL)
FROM mart.hrain_v5_1_aws_valid_audit_20260402
UNION ALL
SELECT
    'C4_drop_reason_by_split',
    'test'::TEXT,
    COUNT(*) FILTER (WHERE temp_c IS NULL),
    COUNT(*) FILTER (WHERE dew_point_c IS NULL),
    COUNT(*) FILTER (WHERE temp_change_3h_c IS NULL),
    COUNT(*) FILTER (WHERE humidity_change_3h_pct IS NULL),
    COUNT(*) FILTER (WHERE moist_energy IS NULL)
FROM mart.hrain_v5_1_aws_test_audit_20260402
ORDER BY split_name;

SELECT
    'C5_drop_by_district_train' AS diagnostic_id,
    district_name,
    COUNT(*) AS dropped_rows
FROM mart.hrain_v5_1_aws_train_audit_20260402
WHERE is_model_input_ready = FALSE
GROUP BY district_name
ORDER BY dropped_rows DESC, district_name;

SELECT
    'C6_drop_by_month_train' AS diagnostic_id,
    to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM') AS year_month,
    COUNT(*) AS dropped_rows
FROM mart.hrain_v5_1_aws_train_audit_20260402
WHERE is_model_input_ready = FALSE
GROUP BY to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')
ORDER BY year_month;

SELECT
    'D1_feature_label_row_count_match' AS diagnostic_id,
    'train'::TEXT AS split_name,
    (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_train_features_20260402) AS feature_rows,
    (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_train_labels_20260402) AS label_rows
UNION ALL
SELECT
    'D1_feature_label_row_count_match',
    'valid'::TEXT,
    (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_valid_features_20260402),
    (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_valid_labels_20260402)
UNION ALL
SELECT
    'D1_feature_label_row_count_match',
    'test'::TEXT,
    (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_test_features_20260402),
    (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_test_labels_20260402)
ORDER BY split_name;

SELECT
    'D2_feature_minus_label_train' AS diagnostic_id,
    COUNT(*) AS feature_rows_missing_label
FROM mart.hrain_v5_1_aws_train_features_20260402 f
LEFT JOIN mart.hrain_v5_1_aws_train_labels_20260402 l
    ON l.district_name = f.district_name
   AND l.base_datetime = f.base_datetime
WHERE l.district_name IS NULL;

SELECT
    'D3_label_minus_feature_train' AS diagnostic_id,
    COUNT(*) AS label_rows_missing_feature
FROM mart.hrain_v5_1_aws_train_labels_20260402 l
LEFT JOIN mart.hrain_v5_1_aws_train_features_20260402 f
    ON f.district_name = l.district_name
   AND f.base_datetime = l.base_datetime
WHERE f.district_name IS NULL;

SELECT
    'D4_duplicate_key_train_features' AS diagnostic_id,
    COUNT(*) AS duplicate_key_group_count
FROM (
    SELECT district_name, base_datetime
    FROM mart.hrain_v5_1_aws_train_features_20260402
    GROUP BY district_name, base_datetime
    HAVING COUNT(*) > 1
) d;

SELECT
    'D5_feature_table_leakage_columns' AS diagnostic_id,
    table_name,
    COUNT(*) FILTER (
        WHERE column_name IN (
            'label',
            'target_rain_1h_mm',
            'target_rain_3h_mm',
            'label_source_point_count',
            'label_window_end',
            'label_ready_at',
            'split_type',
            'label_source_name',
            'label_rule_name',
            'preprocessing_rule_name',
            'data_version'
        )
    ) AS leakage_column_hits
FROM information_schema.columns
WHERE table_schema = 'mart'
  AND table_name IN (
      'hrain_v5_1_aws_train_features_20260402',
      'hrain_v5_1_aws_valid_features_20260402',
      'hrain_v5_1_aws_test_features_20260402'
  )
GROUP BY table_name
ORDER BY table_name;

SELECT
    'D6_jongno_rows_in_any_split' AS diagnostic_id,
    'train'::TEXT AS split_name,
    COUNT(*) FILTER (WHERE district_name = '종로구') AS jongno_rows
FROM mart.hrain_v5_1_aws_train_audit_20260402
UNION ALL
SELECT
    'D6_jongno_rows_in_any_split',
    'valid'::TEXT,
    COUNT(*) FILTER (WHERE district_name = '종로구')
FROM mart.hrain_v5_1_aws_valid_audit_20260402
UNION ALL
SELECT
    'D6_jongno_rows_in_any_split',
    'test'::TEXT,
    COUNT(*) FILTER (WHERE district_name = '종로구')
FROM mart.hrain_v5_1_aws_test_audit_20260402
ORDER BY split_name;
