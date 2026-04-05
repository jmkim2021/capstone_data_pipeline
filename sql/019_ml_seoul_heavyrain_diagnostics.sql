WITH labeled AS (
    SELECT
        b.district_name,
        b.observed_at AS base_datetime,
        f1.precip_mm AS target_rain_1h_mm,
        (COALESCE(f1.precip_mm, 0.0) + COALESCE(f2.precip_mm, 0.0) + COALESCE(f3.precip_mm, 0.0))::DOUBLE PRECISION AS target_rain_3h_mm
    FROM mart.seoul_aws_district_timeline b
    JOIN mart.seoul_aws_district_timeline f1
      ON f1.district_name = b.district_name
     AND f1.observed_at = b.observed_at + INTERVAL '1 hour'
    JOIN mart.seoul_aws_district_timeline f2
      ON f2.district_name = b.district_name
     AND f2.observed_at = b.observed_at + INTERVAL '2 hour'
    JOIN mart.seoul_aws_district_timeline f3
      ON f3.district_name = b.district_name
     AND f3.observed_at = b.observed_at + INTERVAL '3 hour'
    WHERE b.observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
      AND b.observed_at < TIMESTAMPTZ '2025-12-31 21:00:00+09'
      AND f1.precip_mm IS NOT NULL
      AND f2.precip_mm IS NOT NULL
      AND f3.precip_mm IS NOT NULL
)
SELECT
    EXTRACT(YEAR FROM base_datetime)::INTEGER AS base_year,
    EXTRACT(MONTH FROM base_datetime)::INTEGER AS base_month,
    district_name,
    COUNT(*) AS row_count,
    COUNT(*) FILTER (WHERE target_rain_1h_mm >= 10.0) AS event_1h_ge_10mm,
    COUNT(*) FILTER (WHERE target_rain_1h_mm >= 20.0) AS event_1h_ge_20mm,
    COUNT(*) FILTER (WHERE target_rain_1h_mm >= 30.0) AS event_1h_ge_30mm,
    COUNT(*) FILTER (WHERE target_rain_3h_mm >= 20.0) AS event_3h_ge_20mm,
    COUNT(*) FILTER (WHERE target_rain_3h_mm >= 30.0) AS event_3h_ge_30mm,
    COUNT(*) FILTER (WHERE target_rain_3h_mm >= 50.0) AS event_3h_ge_50mm,
    COUNT(*) FILTER (WHERE target_rain_3h_mm >= 60.0) AS event_3h_ge_60mm
FROM labeled
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;

WITH labeled AS (
    SELECT
        b.district_name,
        b.observed_at AS base_datetime,
        f1.precip_mm AS target_rain_1h_mm,
        (COALESCE(f1.precip_mm, 0.0) + COALESCE(f2.precip_mm, 0.0) + COALESCE(f3.precip_mm, 0.0))::DOUBLE PRECISION AS target_rain_3h_mm
    FROM mart.seoul_aws_district_timeline b
    JOIN mart.seoul_aws_district_timeline f1
      ON f1.district_name = b.district_name
     AND f1.observed_at = b.observed_at + INTERVAL '1 hour'
    JOIN mart.seoul_aws_district_timeline f2
      ON f2.district_name = b.district_name
     AND f2.observed_at = b.observed_at + INTERVAL '2 hour'
    JOIN mart.seoul_aws_district_timeline f3
      ON f3.district_name = b.district_name
     AND f3.observed_at = b.observed_at + INTERVAL '3 hour'
    WHERE b.observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
      AND b.observed_at < TIMESTAMPTZ '2025-12-31 21:00:00+09'
      AND f1.precip_mm IS NOT NULL
      AND f2.precip_mm IS NOT NULL
      AND f3.precip_mm IS NOT NULL
)
SELECT
    metric,
    min_value,
    p50,
    p90,
    p95,
    p99,
    max_value
FROM (
    SELECT
        'target_rain_1h_mm' AS metric,
        MIN(target_rain_1h_mm) AS min_value,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY target_rain_1h_mm) AS p50,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY target_rain_1h_mm) AS p90,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY target_rain_1h_mm) AS p95,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY target_rain_1h_mm) AS p99,
        MAX(target_rain_1h_mm) AS max_value
    FROM labeled
    UNION ALL
    SELECT
        'target_rain_3h_mm' AS metric,
        MIN(target_rain_3h_mm) AS min_value,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY target_rain_3h_mm) AS p50,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY target_rain_3h_mm) AS p90,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY target_rain_3h_mm) AS p95,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY target_rain_3h_mm) AS p99,
        MAX(target_rain_3h_mm) AS max_value
    FROM labeled
) s
ORDER BY metric;

WITH labeled AS (
    SELECT
        b.district_name,
        b.observed_at AS base_datetime,
        f1.precip_mm AS target_rain_1h_mm,
        (COALESCE(f1.precip_mm, 0.0) + COALESCE(f2.precip_mm, 0.0) + COALESCE(f3.precip_mm, 0.0))::DOUBLE PRECISION AS target_rain_3h_mm
    FROM mart.seoul_aws_district_timeline b
    JOIN mart.seoul_aws_district_timeline f1
      ON f1.district_name = b.district_name
     AND f1.observed_at = b.observed_at + INTERVAL '1 hour'
    JOIN mart.seoul_aws_district_timeline f2
      ON f2.district_name = b.district_name
     AND f2.observed_at = b.observed_at + INTERVAL '2 hour'
    JOIN mart.seoul_aws_district_timeline f3
      ON f3.district_name = b.district_name
     AND f3.observed_at = b.observed_at + INTERVAL '3 hour'
    WHERE b.observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
      AND b.observed_at < TIMESTAMPTZ '2025-12-31 21:00:00+09'
      AND f1.precip_mm IS NOT NULL
      AND f2.precip_mm IS NOT NULL
      AND f3.precip_mm IS NOT NULL
)
SELECT
    target_definition,
    positive_rows,
    total_rows,
    ROUND(100.0 * positive_rows::NUMERIC / NULLIF(total_rows, 0), 4) AS positive_pct
FROM (
    SELECT '1h >= 10mm' AS target_definition, COUNT(*) FILTER (WHERE target_rain_1h_mm >= 10.0) AS positive_rows, COUNT(*) AS total_rows FROM labeled
    UNION ALL
    SELECT '1h >= 20mm', COUNT(*) FILTER (WHERE target_rain_1h_mm >= 20.0), COUNT(*) FROM labeled
    UNION ALL
    SELECT '1h >= 30mm', COUNT(*) FILTER (WHERE target_rain_1h_mm >= 30.0), COUNT(*) FROM labeled
    UNION ALL
    SELECT '3h >= 20mm', COUNT(*) FILTER (WHERE target_rain_3h_mm >= 20.0), COUNT(*) FROM labeled
    UNION ALL
    SELECT '3h >= 30mm', COUNT(*) FILTER (WHERE target_rain_3h_mm >= 30.0), COUNT(*) FROM labeled
    UNION ALL
    SELECT '3h >= 50mm', COUNT(*) FILTER (WHERE target_rain_3h_mm >= 50.0), COUNT(*) FROM labeled
    UNION ALL
    SELECT '3h >= 60mm', COUNT(*) FILTER (WHERE target_rain_3h_mm >= 60.0), COUNT(*) FROM labeled
    UNION ALL
    SELECT '1h >= 20mm OR 3h >= 50mm', COUNT(*) FILTER (WHERE target_rain_1h_mm >= 20.0 OR target_rain_3h_mm >= 50.0), COUNT(*) FROM labeled
    UNION ALL
    SELECT '1h >= 30mm OR 3h >= 60mm', COUNT(*) FILTER (WHERE target_rain_1h_mm >= 30.0 OR target_rain_3h_mm >= 60.0), COUNT(*) FROM labeled
    UNION ALL
    SELECT '3h >= 15mm', COUNT(*) FILTER (WHERE target_rain_3h_mm >= 15.0), COUNT(*) FROM labeled
    UNION ALL
    SELECT '1h >= 15mm OR 3h >= 40mm', COUNT(*) FILTER (WHERE target_rain_1h_mm >= 15.0 OR target_rain_3h_mm >= 40.0), COUNT(*) FROM labeled
    UNION ALL
    SELECT '1h >= 25mm OR 3h >= 45mm', COUNT(*) FILTER (WHERE target_rain_1h_mm >= 25.0 OR target_rain_3h_mm >= 45.0), COUNT(*) FROM labeled
) s
ORDER BY positive_pct DESC, target_definition;

WITH labeled AS (
    SELECT
        b.district_name,
        b.observed_at AS base_datetime,
        f1.precip_mm AS target_rain_1h_mm,
        (COALESCE(f1.precip_mm, 0.0) + COALESCE(f2.precip_mm, 0.0) + COALESCE(f3.precip_mm, 0.0))::DOUBLE PRECISION AS target_rain_3h_mm,
        CASE
            WHEN b.observed_at < TIMESTAMPTZ '2024-01-01 00:00:00+09' THEN 'train'
            WHEN b.observed_at < TIMESTAMPTZ '2025-01-01 00:00:00+09' THEN 'valid'
            ELSE 'test'
        END AS split_type
    FROM mart.seoul_aws_district_timeline b
    JOIN mart.seoul_aws_district_timeline f1
      ON f1.district_name = b.district_name
     AND f1.observed_at = b.observed_at + INTERVAL '1 hour'
    JOIN mart.seoul_aws_district_timeline f2
      ON f2.district_name = b.district_name
     AND f2.observed_at = b.observed_at + INTERVAL '2 hour'
    JOIN mart.seoul_aws_district_timeline f3
      ON f3.district_name = b.district_name
     AND f3.observed_at = b.observed_at + INTERVAL '3 hour'
    WHERE b.observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
      AND b.observed_at < TIMESTAMPTZ '2025-12-31 21:00:00+09'
      AND f1.precip_mm IS NOT NULL
      AND f2.precip_mm IS NOT NULL
      AND f3.precip_mm IS NOT NULL
)
SELECT
    split_type,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE target_rain_1h_mm >= 30.0 OR target_rain_3h_mm >= 60.0) AS positive_rows_30_60,
    ROUND(100.0 * COUNT(*) FILTER (WHERE target_rain_1h_mm >= 30.0 OR target_rain_3h_mm >= 60.0)::NUMERIC / COUNT(*), 4) AS positive_pct_30_60,
    COUNT(*) FILTER (WHERE target_rain_1h_mm >= 20.0 OR target_rain_3h_mm >= 50.0) AS positive_rows_20_50,
    ROUND(100.0 * COUNT(*) FILTER (WHERE target_rain_1h_mm >= 20.0 OR target_rain_3h_mm >= 50.0)::NUMERIC / COUNT(*), 4) AS positive_pct_20_50
FROM labeled
GROUP BY split_type
ORDER BY CASE split_type WHEN 'train' THEN 1 WHEN 'valid' THEN 2 WHEN 'test' THEN 3 ELSE 9 END;

WITH labeled AS (
    SELECT
        b.district_name,
        b.observed_at AS base_datetime,
        f1.precip_mm AS target_rain_1h_mm,
        (COALESCE(f1.precip_mm, 0.0) + COALESCE(f2.precip_mm, 0.0) + COALESCE(f3.precip_mm, 0.0))::DOUBLE PRECISION AS target_rain_3h_mm
    FROM mart.seoul_aws_district_timeline b
    JOIN mart.seoul_aws_district_timeline f1
      ON f1.district_name = b.district_name
     AND f1.observed_at = b.observed_at + INTERVAL '1 hour'
    JOIN mart.seoul_aws_district_timeline f2
      ON f2.district_name = b.district_name
     AND f2.observed_at = b.observed_at + INTERVAL '2 hour'
    JOIN mart.seoul_aws_district_timeline f3
      ON f3.district_name = b.district_name
     AND f3.observed_at = b.observed_at + INTERVAL '3 hour'
    WHERE b.observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
      AND b.observed_at < TIMESTAMPTZ '2025-12-31 21:00:00+09'
      AND f1.precip_mm IS NOT NULL
      AND f2.precip_mm IS NOT NULL
      AND f3.precip_mm IS NOT NULL
)
SELECT
    EXTRACT(YEAR FROM base_datetime)::INTEGER AS base_year,
    COUNT(*) FILTER (WHERE target_rain_1h_mm >= 30.0 OR target_rain_3h_mm >= 60.0) AS positive_rows_30_60,
    COUNT(*) FILTER (WHERE target_rain_1h_mm >= 20.0 OR target_rain_3h_mm >= 50.0) AS positive_rows_20_50
FROM labeled
GROUP BY 1
ORDER BY 1;

WITH labeled AS (
    SELECT
        b.district_name,
        b.observed_at AS base_datetime,
        f1.precip_mm AS target_rain_1h_mm,
        (COALESCE(f1.precip_mm, 0.0) + COALESCE(f2.precip_mm, 0.0) + COALESCE(f3.precip_mm, 0.0))::DOUBLE PRECISION AS target_rain_3h_mm
    FROM mart.seoul_aws_district_timeline b
    JOIN mart.seoul_aws_district_timeline f1
      ON f1.district_name = b.district_name
     AND f1.observed_at = b.observed_at + INTERVAL '1 hour'
    JOIN mart.seoul_aws_district_timeline f2
      ON f2.district_name = b.district_name
     AND f2.observed_at = b.observed_at + INTERVAL '2 hour'
    JOIN mart.seoul_aws_district_timeline f3
      ON f3.district_name = b.district_name
     AND f3.observed_at = b.observed_at + INTERVAL '3 hour'
    WHERE b.observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
      AND b.observed_at < TIMESTAMPTZ '2025-12-31 21:00:00+09'
      AND f1.precip_mm IS NOT NULL
      AND f2.precip_mm IS NOT NULL
      AND f3.precip_mm IS NOT NULL
)
SELECT
    district_name,
    COUNT(*) FILTER (WHERE target_rain_1h_mm >= 30.0 OR target_rain_3h_mm >= 60.0) AS positive_rows_30_60,
    COUNT(*) FILTER (WHERE target_rain_1h_mm >= 20.0 OR target_rain_3h_mm >= 50.0) AS positive_rows_20_50,
    MAX(target_rain_1h_mm) AS max_target_rain_1h_mm,
    MAX(target_rain_3h_mm) AS max_target_rain_3h_mm
FROM labeled
GROUP BY district_name
ORDER BY positive_rows_20_50 DESC, district_name;

SELECT
    product_type,
    MIN(base_datetime) AS min_base_datetime,
    MAX(base_datetime) AS max_base_datetime,
    COUNT(*) AS row_count
FROM mart.seoul_district_weather_timeline
WHERE product_type IN ('ultra_fcst', 'short_fcst')
GROUP BY product_type
ORDER BY product_type;

WITH final_dataset AS (
    SELECT * FROM ml.seoul_heavyrain_train
    UNION ALL
    SELECT * FROM ml.seoul_heavyrain_valid
    UNION ALL
    SELECT * FROM ml.seoul_heavyrain_test
)
SELECT
    split_type,
    COUNT(*) AS row_count,
    SUM(target_heavy_rain_flag) AS positive_count,
    ROUND(100.0 * AVG(target_heavy_rain_flag::NUMERIC), 4) AS positive_pct,
    MIN(base_datetime) AS min_base_datetime,
    MAX(base_datetime) AS max_base_datetime
FROM final_dataset
GROUP BY split_type
ORDER BY CASE split_type WHEN 'train' THEN 1 WHEN 'valid' THEN 2 WHEN 'test' THEN 3 ELSE 9 END;

WITH final_dataset AS (
    SELECT * FROM ml.seoul_heavyrain_train
    UNION ALL
    SELECT * FROM ml.seoul_heavyrain_valid
    UNION ALL
    SELECT * FROM ml.seoul_heavyrain_test
)
SELECT
    EXTRACT(YEAR FROM base_datetime)::INTEGER AS base_year,
    SUM(target_heavy_rain_flag) AS positive_count
FROM final_dataset
GROUP BY 1
ORDER BY 1;

WITH final_dataset AS (
    SELECT * FROM ml.seoul_heavyrain_train
    UNION ALL
    SELECT * FROM ml.seoul_heavyrain_valid
    UNION ALL
    SELECT * FROM ml.seoul_heavyrain_test
)
SELECT
    district_name,
    SUM(target_heavy_rain_flag) AS positive_count,
    COUNT(*) AS row_count,
    ROUND(100.0 * AVG(target_heavy_rain_flag::NUMERIC), 4) AS positive_pct
FROM final_dataset
GROUP BY district_name
ORDER BY positive_count DESC, district_name;

SELECT
    NOT EXISTS (
        SELECT 1
        FROM ml.seoul_heavyrain_train t
        INNER JOIN ml.seoul_heavyrain_valid v
            ON v.district_name = t.district_name
           AND v.base_datetime = t.base_datetime
    ) AS train_valid_no_overlap,
    NOT EXISTS (
        SELECT 1
        FROM ml.seoul_heavyrain_train t
        INNER JOIN ml.seoul_heavyrain_test x
            ON x.district_name = t.district_name
           AND x.base_datetime = t.base_datetime
    ) AS train_test_no_overlap,
    NOT EXISTS (
        SELECT 1
        FROM ml.seoul_heavyrain_valid v
        INNER JOIN ml.seoul_heavyrain_test x
            ON x.district_name = v.district_name
           AND x.base_datetime = v.base_datetime
    ) AS valid_test_no_overlap;

WITH final_dataset AS (
    SELECT * FROM ml.seoul_heavyrain_train
    UNION ALL
    SELECT * FROM ml.seoul_heavyrain_valid
    UNION ALL
    SELECT * FROM ml.seoul_heavyrain_test
)
SELECT
    split_type,
    ROUND(100.0 * AVG(CASE WHEN aws_precip_mm IS NULL THEN 1 ELSE 0 END)::NUMERIC, 4) AS aws_precip_mm_missing_pct,
    ROUND(100.0 * AVG(CASE WHEN aws_temp_c IS NULL THEN 1 ELSE 0 END)::NUMERIC, 4) AS aws_temp_c_missing_pct,
    ROUND(100.0 * AVG(CASE WHEN aws_humidity_pct IS NULL THEN 1 ELSE 0 END)::NUMERIC, 4) AS aws_humidity_pct_missing_pct,
    ROUND(100.0 * AVG(CASE WHEN lag_rain_1h_mm IS NULL THEN 1 ELSE 0 END)::NUMERIC, 4) AS lag_rain_1h_mm_missing_pct,
    ROUND(100.0 * AVG(CASE WHEN past_rain_3h_mm IS NULL THEN 1 ELSE 0 END)::NUMERIC, 4) AS past_rain_3h_mm_missing_pct
FROM final_dataset
GROUP BY split_type
ORDER BY CASE split_type WHEN 'train' THEN 1 WHEN 'valid' THEN 2 WHEN 'test' THEN 3 ELSE 9 END;

WITH final_dataset AS (
    SELECT * FROM ml.seoul_heavyrain_train
    UNION ALL
    SELECT * FROM ml.seoul_heavyrain_valid
    UNION ALL
    SELECT * FROM ml.seoul_heavyrain_test
)
SELECT
    COUNT(*) FILTER (WHERE target_rain_1h_mm IS NULL) AS target_rain_1h_null_count,
    COUNT(*) FILTER (WHERE target_rain_3h_mm IS NULL) AS target_rain_3h_null_count,
    COUNT(*) FILTER (WHERE target_heavy_rain_flag IS NULL) AS target_flag_null_count
FROM final_dataset;

WITH old_dataset AS (
    SELECT
        'old_dynamic_recent_view' AS dataset_name,
        COUNT(*) AS row_count,
        COUNT(*) FILTER (WHERE target_heavy_rain_flag = 1) AS positive_count,
        MIN(base_datetime) AS min_base_datetime,
        MAX(base_datetime) AS max_base_datetime
    FROM mart.seoul_district_heavyrain_trainset
    WHERE is_trainable = TRUE
),
new_dataset AS (
    SELECT
        'new_fixed_aws_dataset' AS dataset_name,
        COUNT(*) AS row_count,
        COUNT(*) FILTER (WHERE target_heavy_rain_flag = 1) AS positive_count,
        MIN(base_datetime) AS min_base_datetime,
        MAX(base_datetime) AS max_base_datetime
    FROM ml.seoul_heavyrain_dataset_all
)
SELECT *
FROM old_dataset
UNION ALL
SELECT *
FROM new_dataset;

SELECT
    district_name
FROM mart.seoul_district_flood_features
EXCEPT
SELECT DISTINCT
    district_name
FROM ml.seoul_heavyrain_dataset_all
ORDER BY district_name;
