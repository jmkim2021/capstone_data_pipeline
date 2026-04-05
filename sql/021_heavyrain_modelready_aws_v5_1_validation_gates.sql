SET search_path TO mart, std, public;

WITH train_months AS (
    SELECT COUNT(DISTINCT to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')) AS month_count
    FROM mart.hrain_v5_1_aws_train_features_20260402
),
valid_months AS (
    SELECT COUNT(DISTINCT to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')) AS month_count
    FROM mart.hrain_v5_1_aws_valid_features_20260402
),
test_months AS (
    SELECT COUNT(DISTINCT to_char(base_datetime AT TIME ZONE 'Asia/Seoul', 'YYYY-MM')) AS month_count
    FROM mart.hrain_v5_1_aws_test_features_20260402
),
train_key AS (
    SELECT string_agg(district_name, ',' ORDER BY district_name) AS district_key
    FROM (
        SELECT DISTINCT district_name
        FROM mart.hrain_v5_1_aws_train_features_20260402
    ) s
),
valid_key AS (
    SELECT string_agg(district_name, ',' ORDER BY district_name) AS district_key
    FROM (
        SELECT DISTINCT district_name
        FROM mart.hrain_v5_1_aws_valid_features_20260402
    ) s
),
test_key AS (
    SELECT string_agg(district_name, ',' ORDER BY district_name) AS district_key
    FROM (
        SELECT DISTINCT district_name
        FROM mart.hrain_v5_1_aws_test_features_20260402
    ) s
),
stable_key AS (
    SELECT string_agg(district_name, ',' ORDER BY district_name) AS district_key
    FROM mart.hrain_v5_1_aws_stable_districts_20260402
),
feature_schema_key AS (
    SELECT
        table_name,
        string_agg(column_name, ',' ORDER BY ordinal_position) AS schema_key
    FROM information_schema.columns
    WHERE table_schema = 'mart'
      AND table_name IN (
          'hrain_v5_1_aws_train_features_20260402',
          'hrain_v5_1_aws_inference_features_latest_20260402'
      )
    GROUP BY table_name
),
model_input_schema_key AS (
    SELECT
        table_name,
        string_agg(column_name, ',' ORDER BY ordinal_position) AS schema_key
    FROM information_schema.columns
    WHERE table_schema = 'mart'
      AND table_name IN (
          'hrain_v5_1_aws_train_model_input_20260402',
          'hrain_v5_1_aws_inference_model_input_latest_20260402'
      )
    GROUP BY table_name
),
gates AS (
    SELECT
        1 AS gate_id,
        'G01_train_covers_48_months' AS gate_code,
        CASE
            WHEN (SELECT month_count FROM train_months) = 48 THEN 'PASS'
            ELSE 'FAIL'
        END AS verdict
    UNION ALL
    SELECT
        2,
        'G02_valid_covers_12_months',
        CASE
            WHEN (SELECT month_count FROM valid_months) = 12 THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        3,
        'G03_test_covers_12_months',
        CASE
            WHEN (SELECT month_count FROM test_months) = 12 THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        4,
        'G04_split_district_universe_matches_stable_24',
        CASE
            WHEN (SELECT district_key FROM train_key) = (SELECT district_key FROM stable_key)
             AND (SELECT district_key FROM valid_key) = (SELECT district_key FROM stable_key)
             AND (SELECT district_key FROM test_key) = (SELECT district_key FROM stable_key)
             AND (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_stable_districts_20260402) = 24
            THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        5,
        'G05_jongno_excluded_everywhere',
        CASE
            WHEN (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_snapshot_20260402 WHERE district_name = '종로구') = 0
             AND (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_inference_features_latest_20260402 WHERE district_name = '종로구') = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        6,
        'G06_label_policy_fixed_to_20_40',
        CASE
            WHEN (SELECT COUNT(DISTINCT label_rule_name) FROM mart.hrain_v5_1_aws_snapshot_20260402) = 1
             AND (SELECT MIN(label_rule_name) FROM mart.hrain_v5_1_aws_snapshot_20260402) = '1h>=20 or 3h>=40 with lead 0..3'
            THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        7,
        'G07_positive_labels_exist_all_splits',
        CASE
            WHEN (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_train_labels_20260402 WHERE label = 1) > 0
             AND (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_valid_labels_20260402 WHERE label = 1) > 0
             AND (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_test_labels_20260402 WHERE label = 1) > 0
            THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        8,
        'G08_no_split_has_zero_positive_district',
        CASE
            WHEN (
                SELECT COUNT(*)
                FROM (
                    SELECT district_name
                    FROM mart.hrain_v5_1_aws_train_labels_20260402
                    GROUP BY district_name
                    HAVING COUNT(*) FILTER (WHERE label = 1) = 0
                ) q
            ) = 0
             AND (
                SELECT COUNT(*)
                FROM (
                    SELECT district_name
                    FROM mart.hrain_v5_1_aws_valid_labels_20260402
                    GROUP BY district_name
                    HAVING COUNT(*) FILTER (WHERE label = 1) = 0
                ) q
            ) = 0
             AND (
                SELECT COUNT(*)
                FROM (
                    SELECT district_name
                    FROM mart.hrain_v5_1_aws_test_labels_20260402
                    GROUP BY district_name
                    HAVING COUNT(*) FILTER (WHERE label = 1) = 0
                ) q
            ) = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        9,
        'G09_feature_label_1_to_1_row_counts',
        CASE
            WHEN (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_train_features_20260402) = (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_train_labels_20260402)
             AND (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_valid_features_20260402) = (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_valid_labels_20260402)
             AND (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_test_features_20260402) = (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_test_labels_20260402)
            THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        10,
        'G10_no_duplicate_keys_train_features',
        CASE
            WHEN (
                SELECT COUNT(*)
                FROM (
                    SELECT district_name, base_datetime
                    FROM mart.hrain_v5_1_aws_train_features_20260402
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
        'G11_feature_only_has_zero_leakage_columns',
        CASE
            WHEN (
                SELECT COUNT(*)
                FROM information_schema.columns
                WHERE table_schema = 'mart'
                  AND table_name IN (
                      'hrain_v5_1_aws_train_features_20260402',
                      'hrain_v5_1_aws_valid_features_20260402',
                      'hrain_v5_1_aws_test_features_20260402'
                  )
                  AND column_name IN (
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
            ) = 0
            THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        12,
        'G12_drop_rate_under_half_percent_each_split',
        CASE
            WHEN (
                SELECT ((COUNT(*) - SUM(CASE WHEN is_model_input_ready THEN 1 ELSE 0 END))::DOUBLE PRECISION / COUNT(*))
                FROM mart.hrain_v5_1_aws_train_audit_20260402
            ) <= 0.005
             AND (
                SELECT ((COUNT(*) - SUM(CASE WHEN is_model_input_ready THEN 1 ELSE 0 END))::DOUBLE PRECISION / COUNT(*))
                FROM mart.hrain_v5_1_aws_valid_audit_20260402
            ) <= 0.005
             AND (
                SELECT ((COUNT(*) - SUM(CASE WHEN is_model_input_ready THEN 1 ELSE 0 END))::DOUBLE PRECISION / COUNT(*))
                FROM mart.hrain_v5_1_aws_test_audit_20260402
            ) <= 0.005
            THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        13,
        'G13_train_serve_feature_schema_identical',
        CASE
            WHEN (
                SELECT schema_key
                FROM feature_schema_key
                WHERE table_name = 'hrain_v5_1_aws_train_features_20260402'
            ) = (
                SELECT schema_key
                FROM feature_schema_key
                WHERE table_name = 'hrain_v5_1_aws_inference_features_latest_20260402'
            )
            THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        14,
        'G14_train_serve_model_input_schema_identical',
        CASE
            WHEN (
                SELECT schema_key
                FROM model_input_schema_key
                WHERE table_name = 'hrain_v5_1_aws_train_model_input_20260402'
            ) = (
                SELECT schema_key
                FROM model_input_schema_key
                WHERE table_name = 'hrain_v5_1_aws_inference_model_input_latest_20260402'
            )
            THEN 'PASS'
            ELSE 'FAIL'
        END
    UNION ALL
    SELECT
        15,
        'G15_inference_latest_has_24_ready_rows',
        CASE
            WHEN (SELECT COUNT(*) FROM mart.hrain_v5_1_aws_inference_features_latest_20260402) = 24
            THEN 'PASS'
            ELSE 'FAIL'
        END
)
SELECT
    gate_id,
    gate_code,
    verdict
FROM (
    SELECT gate_id, gate_code, verdict
    FROM gates
    UNION ALL
    SELECT
        999 AS gate_id,
        'Z_SUMMARY_MODEL_READY' AS gate_code,
        CASE
            WHEN EXISTS (SELECT 1 FROM gates WHERE verdict = 'FAIL') THEN 'MODEL_READY_NO'
            ELSE 'MODEL_READY_YES'
        END AS verdict
) q
ORDER BY gate_id;
