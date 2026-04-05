BEGIN;

CREATE SCHEMA IF NOT EXISTS mart;

CREATE INDEX IF NOT EXISTS seoul_aws_district_hourly_district_observed_idx
    ON std.seoul_aws_district_hourly (district_name, observed_at);

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'mart'
          AND (
                tablename LIKE 'seoul_district_heavyrain%20260402%'
             OR tablename LIKE 'hrain_v4_aws_%_20260402'
          )
    LOOP
        EXECUTE format('DROP TABLE IF EXISTS mart.%I CASCADE', r.tablename);
    END LOOP;
END
$$;

CREATE TABLE mart.hrain_v4_aws_snapshot_20260402 AS
WITH decision_base AS (
    SELECT
        'aws_hourly'::TEXT AS product_type,
        a.district_name,
        a.observed_at AS base_datetime,
        a.observed_at AS target_datetime,
        0::INTEGER AS lead_minutes,
        a.precip_mm,
        a.temp_c,
        a.humidity_pct
    FROM std.seoul_aws_district_hourly a
    WHERE a.district_name <> '종로구'
      AND a.observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
      AND a.observed_at <= TIMESTAMPTZ '2025-12-31 20:00:00+09'
),
lag_enriched AS (
    SELECT
        b.product_type,
        b.district_name,
        b.base_datetime,
        b.target_datetime,
        b.lead_minutes,
        b.precip_mm,
        b.temp_c,
        b.humidity_pct,
        LAG(b.precip_mm, 1) OVER w AS lag_precip_1h_mm,
        LAG(b.precip_mm, 2) OVER w AS lag_precip_2h_mm,
        LAG(b.temp_c, 3) OVER w AS lag_temp_3h_c,
        LAG(b.humidity_pct, 3) OVER w AS lag_humidity_3h_pct,
        LEAD(b.precip_mm, 1) OVER w AS lead_precip_1h_mm,
        LEAD(b.precip_mm, 2) OVER w AS lead_precip_2h_mm,
        LEAD(b.precip_mm, 3) OVER w AS lead_precip_3h_mm,
        SUM(COALESCE(b.precip_mm, 0.0)) OVER (
            PARTITION BY b.district_name
            ORDER BY b.base_datetime
            ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING
        ) AS target_rain_3h_mm,
        COUNT(*) OVER (
            PARTITION BY b.district_name
            ORDER BY b.base_datetime
            ROWS BETWEEN 1 FOLLOWING AND 1 FOLLOWING
        ) AS future_1h_row_count,
        COUNT(*) OVER (
            PARTITION BY b.district_name
            ORDER BY b.base_datetime
            ROWS BETWEEN 1 FOLLOWING AND 3 FOLLOWING
        ) AS future_3h_row_count
    FROM decision_base b
    WINDOW w AS (PARTITION BY b.district_name ORDER BY b.base_datetime)
),
feature_enriched AS (
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
        e.base_datetime + INTERVAL '3 hours' AS label_window_end,
        e.base_datetime + INTERVAL '3 hours 20 minutes' AS label_ready_at,
        CASE
            WHEN e.future_3h_row_count = 0 THEN 0
            ELSE e.future_3h_row_count
        END AS label_source_point_count,
        CASE
            WHEN e.future_1h_row_count = 0 THEN NULL
            ELSE ROUND(COALESCE(e.lead_precip_1h_mm, 0.0)::NUMERIC, 3)::DOUBLE PRECISION
        END AS target_rain_1h_mm,
        CASE
            WHEN e.future_3h_row_count = 0 THEN NULL
            ELSE ROUND(COALESCE(e.target_rain_3h_mm, 0.0)::NUMERIC, 3)::DOUBLE PRECISION
        END AS target_rain_3h_mm,
        e.lead_precip_1h_mm,
        e.lead_precip_2h_mm,
        e.lead_precip_3h_mm
    FROM lag_enriched e
),
label_enriched AS (
    SELECT
        f.product_type,
        f.district_name,
        f.base_datetime,
        f.target_datetime,
        f.lead_minutes,
        f.precip_mm,
        f.temp_c,
        f.humidity_pct,
        f.dew_point_c,
        f.past_rain_3h_mm,
        f.temp_change_3h_c,
        f.humidity_change_3h_pct,
        f.moist_energy,
        f.label_window_end,
        f.label_ready_at,
        f.label_source_point_count,
        f.target_rain_1h_mm,
        f.target_rain_3h_mm,
        CASE
            WHEN f.target_rain_3h_mm IS NULL THEN NULL
            WHEN COALESCE((f.target_rain_1h_mm >= 20.0), FALSE)
              OR COALESCE((LEAD(f.target_rain_1h_mm, 1) OVER w >= 20.0), FALSE)
              OR COALESCE((LEAD(f.target_rain_1h_mm, 2) OVER w >= 20.0), FALSE)
              OR COALESCE((LEAD(f.target_rain_1h_mm, 3) OVER w >= 20.0), FALSE)
              OR COALESCE((f.target_rain_3h_mm >= 40.0), FALSE)
              OR COALESCE((LEAD(f.target_rain_3h_mm, 1) OVER w >= 40.0), FALSE)
              OR COALESCE((LEAD(f.target_rain_3h_mm, 2) OVER w >= 40.0), FALSE)
              OR COALESCE((LEAD(f.target_rain_3h_mm, 3) OVER w >= 40.0), FALSE)
            THEN 1
            ELSE 0
        END AS label,
        CASE
            WHEN f.base_datetime >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
             AND f.base_datetime <= TIMESTAMPTZ '2023-12-31 23:00:00+09' THEN 'train'
            WHEN f.base_datetime >= TIMESTAMPTZ '2024-01-01 00:00:00+09'
             AND f.base_datetime <= TIMESTAMPTZ '2024-12-31 23:00:00+09' THEN 'valid'
            WHEN f.base_datetime >= TIMESTAMPTZ '2025-01-01 00:00:00+09'
             AND f.base_datetime <= TIMESTAMPTZ '2025-12-31 20:00:00+09' THEN 'test'
            ELSE NULL
        END AS split_type,
        'std.seoul_aws_district_hourly'::TEXT AS label_source_name,
        '1h>=20 or 3h>=40 with lead 0..3'::TEXT AS label_rule_name,
        'seoul_district_heavyrain_v4_aws_modelready'::TEXT AS data_version
    FROM feature_enriched f
    WINDOW w AS (PARTITION BY f.district_name ORDER BY f.base_datetime)
)
SELECT
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
    split_type,
    label_source_name,
    label_rule_name,
    data_version
FROM label_enriched
WHERE split_type IS NOT NULL;

CREATE INDEX hrain_v4_aws_snapshot_20260402_base_idx
    ON mart.hrain_v4_aws_snapshot_20260402 (base_datetime);

CREATE INDEX hrain_v4_aws_snapshot_20260402_district_base_idx
    ON mart.hrain_v4_aws_snapshot_20260402 (district_name, base_datetime);

CREATE TABLE mart.hrain_v4_aws_train_audit_20260402 AS
SELECT
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
    split_type,
    label_source_name,
    label_rule_name,
    data_version
FROM mart.hrain_v4_aws_snapshot_20260402
WHERE split_type = 'train';

CREATE TABLE mart.hrain_v4_aws_valid_audit_20260402 AS
SELECT
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
    split_type,
    label_source_name,
    label_rule_name,
    data_version
FROM mart.hrain_v4_aws_snapshot_20260402
WHERE split_type = 'valid';

CREATE TABLE mart.hrain_v4_aws_test_audit_20260402 AS
SELECT
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
    split_type,
    label_source_name,
    label_rule_name,
    data_version
FROM mart.hrain_v4_aws_snapshot_20260402
WHERE split_type = 'test';

CREATE TABLE mart.hrain_v4_aws_train_features_20260402 AS
SELECT
    district_name,
    base_datetime,
    temp_c,
    precip_mm,
    humidity_pct,
    dew_point_c,
    past_rain_3h_mm,
    temp_change_3h_c,
    humidity_change_3h_pct,
    moist_energy
FROM mart.hrain_v4_aws_train_audit_20260402
WHERE label IS NOT NULL
  AND temp_c IS NOT NULL
  AND precip_mm IS NOT NULL
  AND humidity_pct IS NOT NULL
  AND dew_point_c IS NOT NULL
  AND past_rain_3h_mm IS NOT NULL
  AND temp_change_3h_c IS NOT NULL
  AND humidity_change_3h_pct IS NOT NULL
  AND moist_energy IS NOT NULL;

CREATE TABLE mart.hrain_v4_aws_valid_features_20260402 AS
SELECT
    district_name,
    base_datetime,
    temp_c,
    precip_mm,
    humidity_pct,
    dew_point_c,
    past_rain_3h_mm,
    temp_change_3h_c,
    humidity_change_3h_pct,
    moist_energy
FROM mart.hrain_v4_aws_valid_audit_20260402
WHERE label IS NOT NULL
  AND temp_c IS NOT NULL
  AND precip_mm IS NOT NULL
  AND humidity_pct IS NOT NULL
  AND dew_point_c IS NOT NULL
  AND past_rain_3h_mm IS NOT NULL
  AND temp_change_3h_c IS NOT NULL
  AND humidity_change_3h_pct IS NOT NULL
  AND moist_energy IS NOT NULL;

CREATE TABLE mart.hrain_v4_aws_test_features_20260402 AS
SELECT
    district_name,
    base_datetime,
    temp_c,
    precip_mm,
    humidity_pct,
    dew_point_c,
    past_rain_3h_mm,
    temp_change_3h_c,
    humidity_change_3h_pct,
    moist_energy
FROM mart.hrain_v4_aws_test_audit_20260402
WHERE label IS NOT NULL
  AND temp_c IS NOT NULL
  AND precip_mm IS NOT NULL
  AND humidity_pct IS NOT NULL
  AND dew_point_c IS NOT NULL
  AND past_rain_3h_mm IS NOT NULL
  AND temp_change_3h_c IS NOT NULL
  AND humidity_change_3h_pct IS NOT NULL
  AND moist_energy IS NOT NULL;

CREATE TABLE mart.hrain_v4_aws_train_labels_20260402 AS
SELECT
    district_name,
    base_datetime,
    label
FROM mart.hrain_v4_aws_train_audit_20260402
WHERE label IS NOT NULL
  AND temp_c IS NOT NULL
  AND precip_mm IS NOT NULL
  AND humidity_pct IS NOT NULL
  AND dew_point_c IS NOT NULL
  AND past_rain_3h_mm IS NOT NULL
  AND temp_change_3h_c IS NOT NULL
  AND humidity_change_3h_pct IS NOT NULL
  AND moist_energy IS NOT NULL;

CREATE TABLE mart.hrain_v4_aws_valid_labels_20260402 AS
SELECT
    district_name,
    base_datetime,
    label
FROM mart.hrain_v4_aws_valid_audit_20260402
WHERE label IS NOT NULL
  AND temp_c IS NOT NULL
  AND precip_mm IS NOT NULL
  AND humidity_pct IS NOT NULL
  AND dew_point_c IS NOT NULL
  AND past_rain_3h_mm IS NOT NULL
  AND temp_change_3h_c IS NOT NULL
  AND humidity_change_3h_pct IS NOT NULL
  AND moist_energy IS NOT NULL;

CREATE TABLE mart.hrain_v4_aws_test_labels_20260402 AS
SELECT
    district_name,
    base_datetime,
    label
FROM mart.hrain_v4_aws_test_audit_20260402
WHERE label IS NOT NULL
  AND temp_c IS NOT NULL
  AND precip_mm IS NOT NULL
  AND humidity_pct IS NOT NULL
  AND dew_point_c IS NOT NULL
  AND past_rain_3h_mm IS NOT NULL
  AND temp_change_3h_c IS NOT NULL
  AND humidity_change_3h_pct IS NOT NULL
  AND moist_energy IS NOT NULL;

ANALYZE mart.hrain_v4_aws_snapshot_20260402;
ANALYZE mart.hrain_v4_aws_train_audit_20260402;
ANALYZE mart.hrain_v4_aws_valid_audit_20260402;
ANALYZE mart.hrain_v4_aws_test_audit_20260402;
ANALYZE mart.hrain_v4_aws_train_features_20260402;
ANALYZE mart.hrain_v4_aws_valid_features_20260402;
ANALYZE mart.hrain_v4_aws_test_features_20260402;
ANALYZE mart.hrain_v4_aws_train_labels_20260402;
ANALYZE mart.hrain_v4_aws_valid_labels_20260402;
ANALYZE mart.hrain_v4_aws_test_labels_20260402;

COMMIT;
