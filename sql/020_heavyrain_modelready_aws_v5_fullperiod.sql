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
          AND tablename LIKE 'hrain_v5_aws_%_20260402'
    LOOP
        EXECUTE format('DROP TABLE IF EXISTS mart.%I CASCADE', r.tablename);
    END LOOP;
END
$$;

CREATE TABLE mart.hrain_v5_aws_stable_districts_20260402 AS
WITH train_d AS (
    SELECT DISTINCT district_name
    FROM std.seoul_aws_district_hourly
    WHERE district_name <> '종로구'
      AND observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
      AND observed_at <= TIMESTAMPTZ '2023-12-31 23:00:00+09'
),
valid_d AS (
    SELECT DISTINCT district_name
    FROM std.seoul_aws_district_hourly
    WHERE district_name <> '종로구'
      AND observed_at >= TIMESTAMPTZ '2024-01-01 00:00:00+09'
      AND observed_at <= TIMESTAMPTZ '2024-12-31 23:00:00+09'
),
test_d AS (
    SELECT DISTINCT district_name
    FROM std.seoul_aws_district_hourly
    WHERE district_name <> '종로구'
      AND observed_at >= TIMESTAMPTZ '2025-01-01 00:00:00+09'
      AND observed_at <= TIMESTAMPTZ '2025-12-31 20:00:00+09'
)
SELECT
    t.district_name
FROM train_d t
INNER JOIN valid_d v
    ON v.district_name = t.district_name
INNER JOIN test_d x
    ON x.district_name = t.district_name
ORDER BY t.district_name;

CREATE TABLE mart.hrain_v5_aws_snapshot_20260402 AS
WITH decision_base AS (
    SELECT
        'aws_hourly'::TEXT AS product_type,
        a.district_name,
        a.observed_at AS base_datetime,
        a.observed_at AS target_datetime
    FROM std.seoul_aws_district_hourly a
    INNER JOIN mart.hrain_v5_aws_stable_districts_20260402 s
        ON s.district_name = a.district_name
    WHERE a.observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
      AND a.observed_at <= TIMESTAMPTZ '2025-12-31 20:00:00+09'
),
humid_fwd_grp AS (
    SELECT
        d.product_type,
        d.district_name,
        d.base_datetime,
        d.target_datetime,
        h.observed_at,
        h.temp_c,
        h.precip_mm,
        h.humidity_pct,
        SUM(
            CASE
                WHEN h.humidity_pct IS NOT NULL THEN 1
                ELSE 0
            END
        ) OVER (
            PARTITION BY h.district_name
            ORDER BY h.observed_at
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS humidity_ffwd_grp
    FROM decision_base d
    INNER JOIN std.seoul_aws_district_hourly h
        ON h.district_name = d.district_name
       AND h.observed_at = d.base_datetime
),
humid_ffill_raw AS (
    SELECT
        f.product_type,
        f.district_name,
        f.base_datetime,
        f.target_datetime,
        f.temp_c,
        f.precip_mm,
        f.humidity_pct,
        MAX(f.humidity_pct) OVER (
            PARTITION BY f.district_name, f.humidity_ffwd_grp
            ORDER BY f.base_datetime
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS humidity_locf_raw
    FROM humid_fwd_grp f
),
humid_imputed AS (
    SELECT
        x.product_type,
        x.district_name,
        x.base_datetime,
        x.target_datetime,
        x.temp_c,
        x.precip_mm,
        x.humidity_pct,
        x.humidity_locf_raw,
        ROUND(
            COALESCE(x.humidity_locf_raw, 65.0)::NUMERIC,
            3
        )::DOUBLE PRECISION AS humidity_imputed_pct,
        CASE
            WHEN x.humidity_pct IS NULL
              AND x.humidity_locf_raw IS NULL
            THEN TRUE
            ELSE FALSE
        END AS humidity_used_default_prior,
        CASE
            WHEN x.humidity_pct IS NULL
            THEN TRUE
            ELSE FALSE
        END AS humidity_raw_was_null
    FROM humid_ffill_raw x
),
base_with_lead_lag AS (
    SELECT
        i.product_type,
        i.district_name,
        i.base_datetime,
        i.target_datetime,
        0::INTEGER AS lead_minutes,
        COALESCE(i.precip_mm, 0.0) AS precip_mm_eff,
        i.temp_c,
        i.precip_mm AS precip_mm_observed,
        i.humidity_pct AS humidity_pct_observed,
        i.humidity_imputed_pct,
        i.humidity_used_default_prior,
        i.humidity_raw_was_null,
        LAG(COALESCE(i.precip_mm, 0.0), 1) OVER w AS lag_precip_1h_mm,
        LAG(COALESCE(i.precip_mm, 0.0), 2) OVER w AS lag_precip_2h_mm,
        LAG(i.temp_c, 3) OVER w AS lag_temp_3h_c,
        LAG(i.humidity_imputed_pct, 3) OVER w AS lag_humidity_imputed_3h_pct,
        LEAD(i.precip_mm, 1) OVER w AS lead_precip_1h_mm,
        LEAD(i.precip_mm, 2) OVER w AS lead_precip_2h_mm,
        LEAD(i.precip_mm, 3) OVER w AS lead_precip_3h_mm,
        SUM(COALESCE(i.precip_mm, 0.0)) OVER (
            PARTITION BY i.district_name
            ORDER BY i.base_datetime
            ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING
        ) AS target_rain_3h_mm,
        COUNT(*) OVER (
            PARTITION BY i.district_name
            ORDER BY i.base_datetime
            ROWS BETWEEN 1 FOLLOWING AND 1 FOLLOWING
        ) AS future_1h_row_count,
        COUNT(*) OVER (
            PARTITION BY i.district_name
            ORDER BY i.base_datetime
            ROWS BETWEEN 1 FOLLOWING AND 3 FOLLOWING
        ) AS future_3h_row_count
    FROM humid_imputed i
    WINDOW w AS (PARTITION BY i.district_name ORDER BY i.base_datetime)
),
feature_enriched AS (
    SELECT
        e.product_type,
        e.district_name,
        e.base_datetime,
        e.target_datetime,
        e.lead_minutes,
        e.precip_mm_eff,
        e.precip_mm_observed,
        e.temp_c,
        e.humidity_pct_observed,
        e.humidity_imputed_pct,
        e.humidity_used_default_prior,
        e.humidity_raw_was_null,
        CASE
            WHEN e.humidity_imputed_pct IS NULL OR e.humidity_imputed_pct <= 0 OR e.temp_c IS NULL THEN NULL
            ELSE ROUND(
                ((
                    237.7 * (
                        LN(e.humidity_imputed_pct / 100.0) + (17.27 * e.temp_c) / (237.7 + e.temp_c)
                    )
                ) / (
                    17.27 - (
                        LN(e.humidity_imputed_pct / 100.0) + (17.27 * e.temp_c) / (237.7 + e.temp_c)
                    )
                ))::NUMERIC,
                3
            )::DOUBLE PRECISION
        END AS dew_point_c,
        ROUND(
            (
                COALESCE(e.precip_mm_eff, 0.0)
                + COALESCE(e.lag_precip_1h_mm, 0.0)
                + COALESCE(e.lag_precip_2h_mm, 0.0)
            )::NUMERIC,
            3
        )::DOUBLE PRECISION AS past_rain_3h_mm,
        CASE
            WHEN e.temp_c IS NULL THEN NULL
            ELSE ROUND(
                (e.temp_c - COALESCE(e.lag_temp_3h_c, e.temp_c))::NUMERIC,
                3
            )::DOUBLE PRECISION
        END AS temp_change_3h_c,
        CASE
            WHEN e.humidity_imputed_pct IS NULL THEN NULL
            ELSE ROUND(
                (
                    e.humidity_imputed_pct
                    - COALESCE(e.lag_humidity_imputed_3h_pct, e.humidity_imputed_pct)
                )::NUMERIC,
                3
            )::DOUBLE PRECISION
        END AS humidity_change_3h_pct,
        CASE
            WHEN e.temp_c IS NULL OR e.humidity_imputed_pct IS NULL THEN NULL
            ELSE ROUND(
                ((e.temp_c * e.humidity_imputed_pct) / 100.0)::NUMERIC,
                3
            )::DOUBLE PRECISION
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
    FROM base_with_lead_lag e
),
label_enriched AS (
    SELECT
        f.product_type,
        f.district_name,
        f.base_datetime,
        f.target_datetime,
        f.lead_minutes,
        f.precip_mm_eff,
        f.precip_mm_observed,
        f.temp_c,
        f.humidity_pct_observed,
        f.humidity_imputed_pct,
        f.humidity_used_default_prior,
        f.humidity_raw_was_null,
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
        'seoul_district_heavyrain_v5_aws_modelready'::TEXT AS data_version
    FROM feature_enriched f
    WINDOW w AS (PARTITION BY f.district_name ORDER BY f.base_datetime)
)
SELECT
    product_type,
    district_name,
    base_datetime,
    target_datetime,
    lead_minutes,
    precip_mm_eff,
    precip_mm_observed,
    temp_c,
    humidity_pct_observed,
    humidity_imputed_pct,
    humidity_used_default_prior,
    humidity_raw_was_null,
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

CREATE INDEX hrain_v5_aws_snapshot_20260402_base_idx
    ON mart.hrain_v5_aws_snapshot_20260402 (base_datetime);

CREATE INDEX hrain_v5_aws_snapshot_20260402_district_base_idx
    ON mart.hrain_v5_aws_snapshot_20260402 (district_name, base_datetime);

CREATE TABLE mart.hrain_v5_aws_train_audit_20260402 AS
SELECT
    product_type,
    district_name,
    base_datetime,
    target_datetime,
    lead_minutes,
    precip_mm_eff,
    precip_mm_observed,
    temp_c,
    humidity_pct_observed,
    humidity_imputed_pct,
    humidity_used_default_prior,
    humidity_raw_was_null,
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
FROM mart.hrain_v5_aws_snapshot_20260402
WHERE split_type = 'train';

CREATE TABLE mart.hrain_v5_aws_valid_audit_20260402 AS
SELECT
    product_type,
    district_name,
    base_datetime,
    target_datetime,
    lead_minutes,
    precip_mm_eff,
    precip_mm_observed,
    temp_c,
    humidity_pct_observed,
    humidity_imputed_pct,
    humidity_used_default_prior,
    humidity_raw_was_null,
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
FROM mart.hrain_v5_aws_snapshot_20260402
WHERE split_type = 'valid';

CREATE TABLE mart.hrain_v5_aws_test_audit_20260402 AS
SELECT
    product_type,
    district_name,
    base_datetime,
    target_datetime,
    lead_minutes,
    precip_mm_eff,
    precip_mm_observed,
    temp_c,
    humidity_pct_observed,
    humidity_imputed_pct,
    humidity_used_default_prior,
    humidity_raw_was_null,
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
FROM mart.hrain_v5_aws_snapshot_20260402
WHERE split_type = 'test';

CREATE TABLE mart.hrain_v5_aws_train_features_20260402 AS
SELECT
    district_name,
    base_datetime,
    temp_c,
    precip_mm_eff AS precip_mm,
    humidity_imputed_pct AS humidity_pct,
    dew_point_c,
    past_rain_3h_mm,
    temp_change_3h_c,
    humidity_change_3h_pct,
    moist_energy
FROM mart.hrain_v5_aws_train_audit_20260402
WHERE label IS NOT NULL
  AND temp_c IS NOT NULL
  AND dew_point_c IS NOT NULL
  AND past_rain_3h_mm IS NOT NULL
  AND temp_change_3h_c IS NOT NULL
  AND humidity_change_3h_pct IS NOT NULL
  AND moist_energy IS NOT NULL;

CREATE TABLE mart.hrain_v5_aws_valid_features_20260402 AS
SELECT
    district_name,
    base_datetime,
    temp_c,
    precip_mm_eff AS precip_mm,
    humidity_imputed_pct AS humidity_pct,
    dew_point_c,
    past_rain_3h_mm,
    temp_change_3h_c,
    humidity_change_3h_pct,
    moist_energy
FROM mart.hrain_v5_aws_valid_audit_20260402
WHERE label IS NOT NULL
  AND temp_c IS NOT NULL
  AND dew_point_c IS NOT NULL
  AND past_rain_3h_mm IS NOT NULL
  AND temp_change_3h_c IS NOT NULL
  AND humidity_change_3h_pct IS NOT NULL
  AND moist_energy IS NOT NULL;

CREATE TABLE mart.hrain_v5_aws_test_features_20260402 AS
SELECT
    district_name,
    base_datetime,
    temp_c,
    precip_mm_eff AS precip_mm,
    humidity_imputed_pct AS humidity_pct,
    dew_point_c,
    past_rain_3h_mm,
    temp_change_3h_c,
    humidity_change_3h_pct,
    moist_energy
FROM mart.hrain_v5_aws_test_audit_20260402
WHERE label IS NOT NULL
  AND temp_c IS NOT NULL
  AND dew_point_c IS NOT NULL
  AND past_rain_3h_mm IS NOT NULL
  AND temp_change_3h_c IS NOT NULL
  AND humidity_change_3h_pct IS NOT NULL
  AND moist_energy IS NOT NULL;

CREATE TABLE mart.hrain_v5_aws_train_labels_20260402 AS
SELECT
    district_name,
    base_datetime,
    label
FROM mart.hrain_v5_aws_train_audit_20260402
WHERE label IS NOT NULL
  AND temp_c IS NOT NULL
  AND dew_point_c IS NOT NULL
  AND past_rain_3h_mm IS NOT NULL
  AND temp_change_3h_c IS NOT NULL
  AND humidity_change_3h_pct IS NOT NULL
  AND moist_energy IS NOT NULL;

CREATE TABLE mart.hrain_v5_aws_valid_labels_20260402 AS
SELECT
    district_name,
    base_datetime,
    label
FROM mart.hrain_v5_aws_valid_audit_20260402
WHERE label IS NOT NULL
  AND temp_c IS NOT NULL
  AND dew_point_c IS NOT NULL
  AND past_rain_3h_mm IS NOT NULL
  AND temp_change_3h_c IS NOT NULL
  AND humidity_change_3h_pct IS NOT NULL
  AND moist_energy IS NOT NULL;

CREATE TABLE mart.hrain_v5_aws_test_labels_20260402 AS
SELECT
    district_name,
    base_datetime,
    label
FROM mart.hrain_v5_aws_test_audit_20260402
WHERE label IS NOT NULL
  AND temp_c IS NOT NULL
  AND dew_point_c IS NOT NULL
  AND past_rain_3h_mm IS NOT NULL
  AND temp_change_3h_c IS NOT NULL
  AND humidity_change_3h_pct IS NOT NULL
  AND moist_energy IS NOT NULL;

ANALYZE mart.hrain_v5_aws_stable_districts_20260402;
ANALYZE mart.hrain_v5_aws_snapshot_20260402;
ANALYZE mart.hrain_v5_aws_train_audit_20260402;
ANALYZE mart.hrain_v5_aws_valid_audit_20260402;
ANALYZE mart.hrain_v5_aws_test_audit_20260402;
ANALYZE mart.hrain_v5_aws_train_features_20260402;
ANALYZE mart.hrain_v5_aws_valid_features_20260402;
ANALYZE mart.hrain_v5_aws_test_features_20260402;
ANALYZE mart.hrain_v5_aws_train_labels_20260402;
ANALYZE mart.hrain_v5_aws_valid_labels_20260402;
ANALYZE mart.hrain_v5_aws_test_labels_20260402;

COMMIT;


