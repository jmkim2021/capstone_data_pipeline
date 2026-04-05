SET search_path TO mart, std, public;

WITH bounds AS (
    SELECT
        TIMESTAMPTZ '2020-01-01 00:00:00+09' AS train_min,
        TIMESTAMPTZ '2023-12-31 23:00:00+09' AS train_max,
        TIMESTAMPTZ '2024-01-01 00:00:00+09' AS valid_min,
        TIMESTAMPTZ '2024-12-31 23:00:00+09' AS valid_max,
        TIMESTAMPTZ '2025-01-01 00:00:00+09' AS test_min,
        TIMESTAMPTZ '2025-12-31 20:00:00+09' AS test_max
),
train_key AS (
    SELECT string_agg(district_name, ',' ORDER BY district_name) AS key_txt
    FROM (
        SELECT DISTINCT district_name
        FROM mart.hrain_v5_aws_train_features_20260402
    ) s
),
valid_key AS (
    SELECT string_agg(district_name, ',' ORDER BY district_name) AS key_txt
    FROM (
        SELECT DISTINCT district_name
        FROM mart.hrain_v5_aws_valid_features_20260402
    ) s
),
test_key AS (
    SELECT string_agg(district_name, ',' ORDER BY district_name) AS key_txt
    FROM (
        SELECT DISTINCT district_name
        FROM mart.hrain_v5_aws_test_features_20260402
    ) s
),
stable_key AS (
    SELECT string_agg(district_name, ',' ORDER BY district_name) AS key_txt
    FROM mart.hrain_v5_aws_stable_districts_20260402 s
),
train_months AS (
    SELECT COUNT(DISTINCT to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')) AS month_cnt
    FROM mart.hrain_v5_aws_train_features_20260402
),
expected_train_months AS (
    SELECT 48 AS month_cnt
),
valid_months AS (
    SELECT COUNT(DISTINCT to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')) AS month_cnt
    FROM mart.hrain_v5_aws_valid_features_20260402
),
expected_valid_months AS (
    SELECT 12 AS month_cnt
),
test_months AS (
    SELECT COUNT(DISTINCT to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')) AS month_cnt
    FROM mart.hrain_v5_aws_test_features_20260402
),
expected_test_months AS (
    SELECT 12 AS month_cnt
),
leakage_hits AS (
    SELECT COALESCE(SUM(hit_cnt), 0) AS total_hits
    FROM (
        SELECT COUNT(*) AS hit_cnt        
        FROM information_schema.columns
        WHERE table_schema = 'mart'
          AND table_name = 'hrain_v5_aws_train_features_20260402'
          AND column_name IN (
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
    ) q
),
null_ratio AS (
    SELECT
        MAX(
            CASE
                WHEN total_rows > 0 THEN (null_dew::FLOAT8 / total_rows::FLOAT8)
                ELSE 0.0
            END
        ) AS max_dew_null_ratio
    FROM (
        SELECT
            COUNT(*) AS total_rows,
            COUNT(*) FILTER (WHERE dew_point_c IS NULL) AS null_dew
        FROM mart.hrain_v5_aws_train_features_20260402
    ) r
),
gates AS (
    SELECT
        1 AS gate_id,
        'G01_train_timestamps_within_policy' AS gate_code,
        CASE
            WHEN (
                SELECT MIN(base_datetime) >= (SELECT train_min FROM bounds)
                 AND MAX(base_datetime) <= (SELECT train_max FROM bounds)
                FROM mart.hrain_v5_aws_train_features_20260402
            )
            THEN 'PASS'
            ELSE 'FAIL'
        END AS verdict
    UNION ALL
    SELECT
        2,
        'G02_train_has_48_distinct_months',
        CASE
            WHEN (SELECT month_cnt FROM train_months) = (SELECT month_cnt FROM expected_train_months)
            THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        3,
        'G03_valid_timestamps_and_12_months',
        CASE
            WHEN (
                SELECT MIN(base_datetime) >= (SELECT valid_min FROM bounds)
                 AND MAX(base_datetime) <= (SELECT valid_max FROM bounds)
                FROM mart.hrain_v5_aws_valid_features_20260402
            )
             AND (SELECT month_cnt FROM valid_months) = (SELECT month_cnt FROM expected_valid_months)
            THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        4,
        'G04_test_timestamps_and_12_months',
        CASE
            WHEN (
                SELECT MIN(base_datetime) >= (SELECT test_min FROM bounds)
                 AND MAX(base_datetime) <= (SELECT test_max FROM bounds)
                FROM mart.hrain_v5_aws_test_features_20260402
            )
             AND (SELECT month_cnt FROM test_months) = (SELECT month_cnt FROM expected_test_months)
            THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        5,
        'G05_split_district_universe_matches_stable_table',
        CASE
            WHEN (SELECT key_txt FROM train_key) = (SELECT key_txt FROM stable_key)
             AND (SELECT key_txt FROM valid_key) = (SELECT key_txt FROM stable_key)
             AND (SELECT key_txt FROM test_key) = (SELECT key_txt FROM stable_key)
            THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        6,
        'G06_jongno_absent_from_features_all_splits',
        CASE
            WHEN (
                SELECT COUNT(*)
                FROM mart.hrain_v5_aws_train_features_20260402
                WHERE district_name = '종로구'
            ) = 0
             AND (
                SELECT COUNT(*)
                FROM mart.hrain_v5_aws_valid_features_20260402
                WHERE district_name = '종로구'
            ) = 0
             AND (
                SELECT COUNT(*)
                FROM mart.hrain_v5_aws_test_features_20260402
                WHERE district_name = '종로구'
            ) = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        7,
        'G07_label_one_present_all_splits',
        CASE
            WHEN (
                SELECT COUNT(*) FILTER (WHERE label = 1)
                FROM mart.hrain_v5_aws_train_labels_20260402
            ) > 0
             AND (
                SELECT COUNT(*) FILTER (WHERE label = 1)
                FROM mart.hrain_v5_aws_valid_labels_20260402
            ) > 0
             AND (
                SELECT COUNT(*) FILTER (WHERE label = 1)
                FROM mart.hrain_v5_aws_test_labels_20260402
            ) > 0
            THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        8,
        'G08_train_each_district_has_at_least_one_positive',
        CASE
            WHEN (
                SELECT COUNT(DISTINCT district_name)
                FROM mart.hrain_v5_aws_train_labels_20260402
                WHERE label = 1
            ) = (
                SELECT COUNT(DISTINCT district_name)
                FROM mart.hrain_v5_aws_train_labels_20260402
            )
            THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        9,
        'G09_feature_label_row_counts_match_per_split',
        CASE
            WHEN (
                SELECT COUNT(*) FROM mart.hrain_v5_aws_train_features_20260402
            ) = (
                SELECT COUNT(*) FROM mart.hrain_v5_aws_train_labels_20260402
            )
             AND (
                SELECT COUNT(*) FROM mart.hrain_v5_aws_valid_features_20260402
            ) = (
                SELECT COUNT(*) FROM mart.hrain_v5_aws_valid_labels_20260402
            )
             AND (
                SELECT COUNT(*) FROM mart.hrain_v5_aws_test_features_20260402
            ) = (
                SELECT COUNT(*) FROM mart.hrain_v5_aws_test_labels_20260402
            )
            THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        10,
        'G10_no_duplicate_keys_in_train_features',
        CASE
            WHEN (
                SELECT COUNT(*)
                FROM (
                    SELECT district_name, base_datetime
                    FROM mart.hrain_v5_aws_train_features_20260402
                    GROUP BY district_name, base_datetime
                    HAVING COUNT(*) > 1
                ) d
            ) = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        11,
        'G11_feature_only_has_zero_leakage_column_hits',
        CASE
            WHEN (SELECT total_hits FROM leakage_hits) = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        12,
        'G12_train_feature_null_ratio_non_fatal_benchmark_dew_point',
        CASE
            WHEN (SELECT max_dew_null_ratio FROM null_ratio) <= 0.000001
            THEN 'PASS'
            ELSE 'FAIL'
        END
)
SELECT
    gate_id,
    gate_code,
    verdict
FROM (
    SELECT
        gate_id,
        gate_code,
        verdict
    FROM gates
    UNION ALL
    SELECT
        999 AS gate_id,
        'Z_SUMMARY_MODEL_READY' AS gate_code,
        CASE
            WHEN EXISTS (SELECT 1 FROM gates WHERE verdict = 'FAIL')
            THEN 'MODEL_READY_NO'
            ELSE 'MODEL_READY_YES'
        END AS verdict
) AS gate_report
ORDER BY gate_id;


