-- A. 라벨 원천 후보별 데이터 존재 여부
SELECT
    'mart.seoul_rainfall_district_latest' AS source_table,
    COUNT(*) AS total_rows,
    MIN(observed_at) AS min_ts,
    MAX(observed_at) AS max_ts,
    COUNT(DISTINCT district_name) AS distinct_district_count,
    COUNT(*) FILTER (
        WHERE observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
          AND observed_at <= TIMESTAMPTZ '2025-12-31 23:59:59+09'
    ) AS rows_2020_2025
FROM mart.seoul_rainfall_district_latest
UNION ALL
SELECT
    'mart.seoul_aws_district_timeline' AS source_table,
    COUNT(*) AS total_rows,
    MIN(observed_at) AS min_ts,
    MAX(observed_at) AS max_ts,
    COUNT(DISTINCT district_name) AS distinct_district_count,
    COUNT(*) FILTER (
        WHERE observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
          AND observed_at <= TIMESTAMPTZ '2025-12-31 23:59:59+09'
    ) AS rows_2020_2025
FROM mart.seoul_aws_district_timeline;

SELECT
    'mart.seoul_rainfall_district_latest' AS source_table,
    district_name,
    COUNT(*) AS row_count
FROM mart.seoul_rainfall_district_latest
GROUP BY district_name
ORDER BY row_count DESC, district_name;

SELECT
    'mart.seoul_aws_district_timeline' AS source_table,
    district_name,
    COUNT(*) AS row_count
FROM mart.seoul_aws_district_timeline
GROUP BY district_name
ORDER BY row_count DESC, district_name;

-- B. 조인 키 진단
WITH ultra AS (
    SELECT DISTINCT district_name
    FROM mart.seoul_district_ultra_now
    WHERE base_datetime >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
      AND base_datetime <= TIMESTAMPTZ '2025-12-31 23:00:00+09'
),
rain AS (
    SELECT DISTINCT district_name
    FROM mart.seoul_rainfall_district_latest
),
aws AS (
    SELECT DISTINCT district_name
    FROM mart.seoul_aws_district_timeline
)
SELECT
    'ultra_not_in_rain' AS gap_type,
    u.district_name
FROM ultra u
LEFT JOIN rain r
    ON r.district_name = u.district_name
WHERE r.district_name IS NULL
UNION ALL
SELECT
    'rain_not_in_ultra' AS gap_type,
    r.district_name
FROM rain r
LEFT JOIN ultra u
    ON u.district_name = r.district_name
WHERE u.district_name IS NULL
UNION ALL
SELECT
    'ultra_not_in_aws' AS gap_type,
    u.district_name
FROM ultra u
LEFT JOIN aws a
    ON a.district_name = u.district_name
WHERE a.district_name IS NULL
UNION ALL
SELECT
    'aws_not_in_ultra' AS gap_type,
    a.district_name
FROM aws a
LEFT JOIN ultra u
    ON u.district_name = a.district_name
WHERE u.district_name IS NULL
ORDER BY gap_type, district_name;

SELECT
    'mart.seoul_district_ultra_now' AS source_table,
    COUNT(*) FILTER (WHERE district_name IS NULL) AS district_null_rows,
    COUNT(*) FILTER (WHERE district_name <> BTRIM(district_name)) AS district_trim_mismatch_rows
FROM mart.seoul_district_ultra_now
UNION ALL
SELECT
    'mart.seoul_rainfall_district_latest' AS source_table,
    COUNT(*) FILTER (WHERE district_name IS NULL) AS district_null_rows,
    COUNT(*) FILTER (WHERE district_name <> BTRIM(district_name)) AS district_trim_mismatch_rows
FROM mart.seoul_rainfall_district_latest
UNION ALL
SELECT
    'mart.seoul_aws_district_timeline' AS source_table,
    COUNT(*) FILTER (WHERE district_name IS NULL) AS district_null_rows,
    COUNT(*) FILTER (WHERE district_name <> BTRIM(district_name)) AS district_trim_mismatch_rows
FROM mart.seoul_aws_district_timeline;

-- C. 시간축 진단
SELECT
    pg_typeof(u.base_datetime) AS ultra_base_datetime_type,
    pg_typeof(r.observed_at) AS rainfall_observed_at_type
FROM mart.seoul_district_ultra_now u
CROSS JOIN mart.seoul_rainfall_district_latest r
LIMIT 1;

SELECT
    pg_typeof(u.base_datetime) AS ultra_base_datetime_type,
    pg_typeof(a.observed_at) AS aws_observed_at_type
FROM mart.seoul_district_ultra_now u
CROSS JOIN mart.seoul_aws_district_timeline a
LIMIT 1;

WITH base AS (
    SELECT
        district_name,
        base_datetime
    FROM mart.seoul_district_ultra_now
    WHERE district_name = '강남구'
      AND base_datetime >= TIMESTAMPTZ '2024-01-01 00:00:00+09'
      AND base_datetime < TIMESTAMPTZ '2024-01-02 00:00:00+09'
    ORDER BY base_datetime
    LIMIT 20
)
SELECT
    b.base_datetime,
    (
        SELECT COUNT(*)
        FROM mart.seoul_rainfall_district_latest r
        WHERE r.district_name = b.district_name
          AND r.observed_at > b.base_datetime
          AND r.observed_at <= b.base_datetime + INTERVAL '3 hours'
    ) AS rain_rows_window_gt_3h,
    (
        SELECT COUNT(*)
        FROM mart.seoul_aws_district_timeline a
        WHERE a.district_name = b.district_name
          AND a.observed_at > b.base_datetime
          AND a.observed_at <= b.base_datetime + INTERVAL '3 hours'
    ) AS aws_rows_window_gt_3h
FROM base b
ORDER BY b.base_datetime;

WITH base AS (
    SELECT
        district_name,
        base_datetime
    FROM mart.seoul_district_ultra_now
    WHERE base_datetime >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
      AND base_datetime <= TIMESTAMPTZ '2025-12-31 20:00:00+09'
)
SELECT
    'rain_gt_3h' AS boundary_rule,
    COUNT(*) FILTER (
        WHERE EXISTS (
            SELECT 1
            FROM mart.seoul_rainfall_district_latest r
            WHERE r.district_name = b.district_name
              AND r.observed_at > b.base_datetime
              AND r.observed_at <= b.base_datetime + INTERVAL '3 hours'
        )
    ) AS hit_rows,
    COUNT(*) AS total_rows
FROM base b
UNION ALL
SELECT
    'rain_ge_3h' AS boundary_rule,
    COUNT(*) FILTER (
        WHERE EXISTS (
            SELECT 1
            FROM mart.seoul_rainfall_district_latest r
            WHERE r.district_name = b.district_name
              AND r.observed_at >= b.base_datetime
              AND r.observed_at <= b.base_datetime + INTERVAL '3 hours'
        )
    ) AS hit_rows,
    COUNT(*) AS total_rows
FROM base b
UNION ALL
SELECT
    'rain_gt_3h20' AS boundary_rule,
    COUNT(*) FILTER (
        WHERE EXISTS (
            SELECT 1
            FROM mart.seoul_rainfall_district_latest r
            WHERE r.district_name = b.district_name
              AND r.observed_at > b.base_datetime
              AND r.observed_at <= b.base_datetime + INTERVAL '3 hours 20 minutes'
        )
    ) AS hit_rows,
    COUNT(*) AS total_rows
FROM base b
UNION ALL
SELECT
    'aws_gt_3h' AS boundary_rule,
    COUNT(*) FILTER (
        WHERE EXISTS (
            SELECT 1
            FROM mart.seoul_aws_district_timeline a
            WHERE a.district_name = b.district_name
              AND a.observed_at > b.base_datetime
              AND a.observed_at <= b.base_datetime + INTERVAL '3 hours'
        )
    ) AS hit_rows,
    COUNT(*) AS total_rows
FROM base b
UNION ALL
SELECT
    'aws_ge_3h' AS boundary_rule,
    COUNT(*) FILTER (
        WHERE EXISTS (
            SELECT 1
            FROM mart.seoul_aws_district_timeline a
            WHERE a.district_name = b.district_name
              AND a.observed_at >= b.base_datetime
              AND a.observed_at <= b.base_datetime + INTERVAL '3 hours'
        )
    ) AS hit_rows,
    COUNT(*) AS total_rows
FROM base b
UNION ALL
SELECT
    'aws_gt_3h20' AS boundary_rule,
    COUNT(*) FILTER (
        WHERE EXISTS (
            SELECT 1
            FROM mart.seoul_aws_district_timeline a
            WHERE a.district_name = b.district_name
              AND a.observed_at > b.base_datetime
              AND a.observed_at <= b.base_datetime + INTERVAL '3 hours 20 minutes'
        )
    ) AS hit_rows,
    COUNT(*) AS total_rows
FROM base b;

-- D. 라벨 수율 진단
WITH base AS (
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
        x.label_source_point_count,
        x.target_rain_1h_mm,
        x.target_rain_3h_mm,
        CASE
            WHEN x.target_rain_3h_mm IS NULL THEN NULL
            WHEN COALESCE((x.target_rain_1h_mm >= 20.0), FALSE)
              OR COALESCE((LEAD(x.target_rain_1h_mm, 1) OVER w >= 20.0), FALSE)
              OR COALESCE((LEAD(x.target_rain_1h_mm, 2) OVER w >= 20.0), FALSE)
              OR COALESCE((LEAD(x.target_rain_1h_mm, 3) OVER w >= 20.0), FALSE)
              OR COALESCE((x.target_rain_3h_mm >= 40.0), FALSE)
              OR COALESCE((LEAD(x.target_rain_3h_mm, 1) OVER w >= 40.0), FALSE)
              OR COALESCE((LEAD(x.target_rain_3h_mm, 2) OVER w >= 40.0), FALSE)
              OR COALESCE((LEAD(x.target_rain_3h_mm, 3) OVER w >= 40.0), FALSE)
            THEN 1
            ELSE 0
        END AS label
    FROM base b
    LEFT JOIN LATERAL (
        SELECT
            COUNT(r.observed_at) AS label_source_point_count,
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
    WINDOW w AS (PARTITION BY b.district_name ORDER BY b.base_datetime)
),
aws_join AS (
    SELECT
        b.district_name,
        b.base_datetime,
        x.label_source_point_count,
        x.target_rain_1h_mm,
        x.target_rain_3h_mm,
        CASE
            WHEN x.target_rain_3h_mm IS NULL THEN NULL
            WHEN COALESCE((x.target_rain_1h_mm >= 20.0), FALSE)
              OR COALESCE((LEAD(x.target_rain_1h_mm, 1) OVER w >= 20.0), FALSE)
              OR COALESCE((LEAD(x.target_rain_1h_mm, 2) OVER w >= 20.0), FALSE)
              OR COALESCE((LEAD(x.target_rain_1h_mm, 3) OVER w >= 20.0), FALSE)
              OR COALESCE((x.target_rain_3h_mm >= 40.0), FALSE)
              OR COALESCE((LEAD(x.target_rain_3h_mm, 1) OVER w >= 40.0), FALSE)
              OR COALESCE((LEAD(x.target_rain_3h_mm, 2) OVER w >= 40.0), FALSE)
              OR COALESCE((LEAD(x.target_rain_3h_mm, 3) OVER w >= 40.0), FALSE)
            THEN 1
            ELSE 0
        END AS label
    FROM base b
    LEFT JOIN LATERAL (
        SELECT
            COUNT(a.observed_at) AS label_source_point_count,
            CASE
                WHEN COUNT(a.observed_at) FILTER (
                    WHERE a.observed_at <= b.base_datetime + INTERVAL '1 hour'
                ) = 0 THEN NULL
                ELSE ROUND(
                    SUM(COALESCE(a.precip_mm, 0.0)) FILTER (
                        WHERE a.observed_at <= b.base_datetime + INTERVAL '1 hour'
                    )::NUMERIC,
                    3
                )::DOUBLE PRECISION
            END AS target_rain_1h_mm,
            CASE
                WHEN COUNT(a.observed_at) = 0 THEN NULL
                ELSE ROUND(SUM(COALESCE(a.precip_mm, 0.0))::NUMERIC, 3)::DOUBLE PRECISION
            END AS target_rain_3h_mm
        FROM std.seoul_aws_district_hourly a
        WHERE a.district_name = b.district_name
          AND a.observed_at > b.base_datetime
          AND a.observed_at <= b.base_datetime + INTERVAL '3 hours'
    ) x ON TRUE
    WINDOW w AS (PARTITION BY b.district_name ORDER BY b.base_datetime)
)
SELECT
    'rainfall_latest' AS source_name,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE label_source_point_count > 0) AS join_hit_rows,
    COUNT(*) FILTER (WHERE target_rain_1h_mm IS NOT NULL) AS target_rain_1h_non_null_rows,
    COUNT(*) FILTER (WHERE target_rain_3h_mm IS NOT NULL) AS target_rain_3h_non_null_rows,
    COUNT(*) FILTER (WHERE label IS NOT NULL) AS label_non_null_rows,
    COUNT(*) FILTER (WHERE label = 1) AS label_1_rows,
    COUNT(*) FILTER (WHERE label = 0) AS label_0_rows
FROM rain_join
UNION ALL
SELECT
    'aws_hourly' AS source_name,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE label_source_point_count > 0) AS join_hit_rows,
    COUNT(*) FILTER (WHERE target_rain_1h_mm IS NOT NULL) AS target_rain_1h_non_null_rows,
    COUNT(*) FILTER (WHERE target_rain_3h_mm IS NOT NULL) AS target_rain_3h_non_null_rows,
    COUNT(*) FILTER (WHERE label IS NOT NULL) AS label_non_null_rows,
    COUNT(*) FILTER (WHERE label = 1) AS label_1_rows,
    COUNT(*) FILTER (WHERE label = 0) AS label_0_rows
FROM aws_join;
