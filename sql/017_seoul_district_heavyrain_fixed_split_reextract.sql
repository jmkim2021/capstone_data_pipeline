BEGIN;

CREATE SCHEMA IF NOT EXISTS mart;

CREATE INDEX IF NOT EXISTS seoul_district_ultra_now_district_base_idx
    ON mart.seoul_district_ultra_now (district_name, base_datetime);

CREATE INDEX IF NOT EXISTS seoul_rainfall_district_latest_district_observed_idx
    ON mart.seoul_rainfall_district_latest (district_name, observed_at);

DROP TABLE IF EXISTS mart.seoul_district_heavyrain_snapshot_fixed_v2_20260401;
DROP TABLE IF EXISTS mart.seoul_district_heavyrain_train_fixed_v2_20260401;
DROP TABLE IF EXISTS mart.seoul_district_heavyrain_valid_fixed_v2_20260401;
DROP TABLE IF EXISTS mart.seoul_district_heavyrain_test_fixed_v2_20260401;

CREATE TABLE mart.seoul_district_heavyrain_snapshot_fixed_v2_20260401 AS
WITH decision_base AS (
    SELECT
        'ultra_now'::TEXT AS product_type,
        u.district_name,
        u.base_datetime,
        u.base_datetime AS target_datetime,
        0::INTEGER AS lead_minutes,
        u.rain_1h_mm AS precip_mm,
        u.temp_c,
        u.humidity_pct
    FROM mart.seoul_district_ultra_now u
    WHERE u.base_datetime >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
      AND u.base_datetime <= TIMESTAMPTZ '2025-12-31 23:00:00+09'
),
lag_enriched AS (
    SELECT
        b.*,
        l1.rain_1h_mm AS lag_precip_1h_mm,
        l2.rain_1h_mm AS lag_precip_2h_mm,
        l3.temp_c AS lag_temp_3h_c,
        l3.humidity_pct AS lag_humidity_3h_pct
    FROM decision_base b
    LEFT JOIN mart.seoul_district_ultra_now l1
        ON l1.district_name = b.district_name
       AND l1.base_datetime = b.base_datetime - INTERVAL '1 hour'
    LEFT JOIN mart.seoul_district_ultra_now l2
        ON l2.district_name = b.district_name
       AND l2.base_datetime = b.base_datetime - INTERVAL '2 hours'
    LEFT JOIN mart.seoul_district_ultra_now l3
        ON l3.district_name = b.district_name
       AND l3.base_datetime = b.base_datetime - INTERVAL '3 hours'
),
label_enriched AS (
    SELECT
        b.*,
        b.base_datetime + INTERVAL '3 hours' AS label_window_end,
        b.base_datetime + INTERVAL '3 hours 20 minutes' AS label_ready_at,
        label_data.label_source_point_count,
        label_data.target_rain_1h_mm,
        label_data.target_rain_3h_mm
    FROM lag_enriched b
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
                ELSE ROUND(
                    SUM(COALESCE(r.max_rain_10m_mm, 0.0))::NUMERIC,
                    3
                )::DOUBLE PRECISION
            END AS target_rain_3h_mm
        FROM mart.seoul_rainfall_district_latest r
        WHERE r.district_name = b.district_name
          AND r.observed_at > b.base_datetime
          AND r.observed_at <= b.base_datetime + INTERVAL '3 hours'
    ) label_data ON TRUE
),
label_rule_enriched AS (
    SELECT
        e.*,
        CASE
            WHEN e.target_rain_3h_mm IS NULL THEN NULL
            WHEN COALESCE((e.target_rain_1h_mm >= 20.0), FALSE)
              OR COALESCE((LEAD(e.target_rain_1h_mm, 1) OVER w >= 20.0), FALSE)
              OR COALESCE((LEAD(e.target_rain_1h_mm, 2) OVER w >= 20.0), FALSE)
              OR COALESCE((LEAD(e.target_rain_1h_mm, 3) OVER w >= 20.0), FALSE)
              OR COALESCE((e.target_rain_3h_mm >= 40.0), FALSE)
              OR COALESCE((LEAD(e.target_rain_3h_mm, 1) OVER w >= 40.0), FALSE)
              OR COALESCE((LEAD(e.target_rain_3h_mm, 2) OVER w >= 40.0), FALSE)
              OR COALESCE((LEAD(e.target_rain_3h_mm, 3) OVER w >= 40.0), FALSE)
            THEN 1
            ELSE 0
        END AS label
    FROM label_enriched e
    WINDOW w AS (PARTITION BY e.district_name ORDER BY e.base_datetime)
)
SELECT
    e.product_type,
    e.district_name,
    e.base_datetime,
    e.target_datetime,
    e.lead_minutes,
    e.precip_mm,
    e.temp_c,
    e.humidity_pct,
    CASE
        WHEN e.humidity_pct IS NULL OR e.humidity_pct <= 0 OR e.temp_c IS NULL THEN NULL
        ELSE ROUND(
            ((
                237.7 * (
                    LN(e.humidity_pct / 100.0) + (17.27 * e.temp_c) / (237.7 + e.temp_c)
                )
            ) / (
                17.27 - (
                    LN(e.humidity_pct / 100.0) + (17.27 * e.temp_c) / (237.7 + e.temp_c)
                )
            ))::NUMERIC,
            3
        )::DOUBLE PRECISION
    END AS dew_point_c,
    CASE
        WHEN e.precip_mm IS NULL OR e.lag_precip_1h_mm IS NULL OR e.lag_precip_2h_mm IS NULL THEN NULL
        ELSE ROUND(
            (COALESCE(e.precip_mm, 0.0) + COALESCE(e.lag_precip_1h_mm, 0.0) + COALESCE(e.lag_precip_2h_mm, 0.0))::NUMERIC,
            3
        )::DOUBLE PRECISION
    END AS past_rain_3h_mm,
    CASE
        WHEN e.temp_c IS NULL OR e.lag_temp_3h_c IS NULL THEN NULL
        ELSE ROUND((e.temp_c - e.lag_temp_3h_c)::NUMERIC, 3)::DOUBLE PRECISION
    END AS temp_change_3h_c,
    CASE
        WHEN e.humidity_pct IS NULL OR e.lag_humidity_3h_pct IS NULL THEN NULL
        ELSE ROUND((e.humidity_pct - e.lag_humidity_3h_pct)::NUMERIC, 3)::DOUBLE PRECISION
    END AS humidity_change_3h_pct,
    CASE
        WHEN e.temp_c IS NULL OR e.humidity_pct IS NULL THEN NULL
        ELSE ROUND(((e.temp_c * e.humidity_pct) / 100.0)::NUMERIC, 3)::DOUBLE PRECISION
    END AS moist_energy,
    e.label_window_end,
    e.label_ready_at,
    e.label_source_point_count,
    e.target_rain_1h_mm,
    e.target_rain_3h_mm,
    e.label,
    CASE
        WHEN CURRENT_TIMESTAMP < e.label_ready_at THEN 'pending'
        ELSE 'labeled'
    END AS dataset_status,
    CASE
        WHEN CURRENT_TIMESTAMP < e.label_ready_at THEN FALSE
        WHEN e.target_rain_3h_mm IS NULL THEN FALSE
        ELSE TRUE
    END AS is_trainable,
    CASE
        WHEN e.base_datetime >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
         AND e.base_datetime <= TIMESTAMPTZ '2023-12-31 23:00:00+09' THEN 'train'
        WHEN e.base_datetime >= TIMESTAMPTZ '2024-01-01 00:00:00+09'
         AND e.base_datetime <= TIMESTAMPTZ '2024-12-31 23:00:00+09' THEN 'valid'
        WHEN e.base_datetime >= TIMESTAMPTZ '2025-01-01 00:00:00+09'
         AND e.base_datetime <= TIMESTAMPTZ '2025-12-31 20:00:00+09' THEN 'test'
        ELSE NULL
    END AS split_type,
    'seoul_district_heavyrain_v2'::TEXT AS data_version
FROM label_rule_enriched e
WHERE (
        (e.base_datetime >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
         AND e.base_datetime <= TIMESTAMPTZ '2023-12-31 23:00:00+09')
     OR (e.base_datetime >= TIMESTAMPTZ '2024-01-01 00:00:00+09'
         AND e.base_datetime <= TIMESTAMPTZ '2024-12-31 23:00:00+09')
     OR (e.base_datetime >= TIMESTAMPTZ '2025-01-01 00:00:00+09'
         AND e.base_datetime <= TIMESTAMPTZ '2025-12-31 20:00:00+09')
      );

CREATE INDEX seoul_district_heavyrain_snapshot_fixed_v2_20260401_base_idx
    ON mart.seoul_district_heavyrain_snapshot_fixed_v2_20260401 (base_datetime);

CREATE INDEX seoul_district_heavyrain_snapshot_fixed_v2_20260401_district_base_idx
    ON mart.seoul_district_heavyrain_snapshot_fixed_v2_20260401 (district_name, base_datetime);

CREATE TABLE mart.seoul_district_heavyrain_train_fixed_v2_20260401 AS
SELECT
    s.product_type,
    s.district_name,
    s.base_datetime,
    s.target_datetime,
    s.lead_minutes,
    s.precip_mm,
    s.temp_c,
    s.humidity_pct,
    s.dew_point_c,
    s.past_rain_3h_mm,
    s.temp_change_3h_c,
    s.humidity_change_3h_pct,
    s.moist_energy,
    s.label_window_end,
    s.label_ready_at,
    s.label_source_point_count,
    s.target_rain_1h_mm,
    s.target_rain_3h_mm,
    s.label,
    s.dataset_status,
    s.is_trainable,
    s.split_type,
    s.data_version
FROM mart.seoul_district_heavyrain_snapshot_fixed_v2_20260401 s
WHERE s.split_type = 'train';

CREATE INDEX seoul_district_heavyrain_train_fixed_v2_20260401_base_idx
    ON mart.seoul_district_heavyrain_train_fixed_v2_20260401 (base_datetime);

CREATE TABLE mart.seoul_district_heavyrain_valid_fixed_v2_20260401 AS
SELECT
    s.product_type,
    s.district_name,
    s.base_datetime,
    s.target_datetime,
    s.lead_minutes,
    s.precip_mm,
    s.temp_c,
    s.humidity_pct,
    s.dew_point_c,
    s.past_rain_3h_mm,
    s.temp_change_3h_c,
    s.humidity_change_3h_pct,
    s.moist_energy,
    s.label_window_end,
    s.label_ready_at,
    s.label_source_point_count,
    s.target_rain_1h_mm,
    s.target_rain_3h_mm,
    s.label,
    s.dataset_status,
    s.is_trainable,
    s.split_type,
    s.data_version
FROM mart.seoul_district_heavyrain_snapshot_fixed_v2_20260401 s
WHERE s.split_type = 'valid';

CREATE INDEX seoul_district_heavyrain_valid_fixed_v2_20260401_base_idx
    ON mart.seoul_district_heavyrain_valid_fixed_v2_20260401 (base_datetime);

CREATE TABLE mart.seoul_district_heavyrain_test_fixed_v2_20260401 AS
SELECT
    s.product_type,
    s.district_name,
    s.base_datetime,
    s.target_datetime,
    s.lead_minutes,
    s.precip_mm,
    s.temp_c,
    s.humidity_pct,
    s.dew_point_c,
    s.past_rain_3h_mm,
    s.temp_change_3h_c,
    s.humidity_change_3h_pct,
    s.moist_energy,
    s.label_window_end,
    s.label_ready_at,
    s.label_source_point_count,
    s.target_rain_1h_mm,
    s.target_rain_3h_mm,
    s.label,
    s.dataset_status,
    s.is_trainable,
    s.split_type,
    s.data_version
FROM mart.seoul_district_heavyrain_snapshot_fixed_v2_20260401 s
WHERE s.split_type = 'test';

CREATE INDEX seoul_district_heavyrain_test_fixed_v2_20260401_base_idx
    ON mart.seoul_district_heavyrain_test_fixed_v2_20260401 (base_datetime);

ANALYZE mart.seoul_district_heavyrain_snapshot_fixed_v2_20260401;
ANALYZE mart.seoul_district_heavyrain_train_fixed_v2_20260401;
ANALYZE mart.seoul_district_heavyrain_valid_fixed_v2_20260401;
ANALYZE mart.seoul_district_heavyrain_test_fixed_v2_20260401;

COMMIT;
