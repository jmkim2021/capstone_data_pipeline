BEGIN;

CREATE SCHEMA IF NOT EXISTS mart;

CREATE INDEX IF NOT EXISTS seoul_aws_district_hourly_district_observed_idx
    ON std.seoul_aws_district_hourly (district_name, observed_at);

DROP VIEW IF EXISTS mart.hrain_v5_1_aws_inference_model_input_latest_20260402 CASCADE;
DROP VIEW IF EXISTS mart.hrain_v5_1_aws_inference_features_latest_20260402 CASCADE;
DROP VIEW IF EXISTS mart.hrain_v5_1_aws_inference_audit_latest_20260402 CASCADE;
DROP VIEW IF EXISTS mart.hrain_v5_1_aws_feature_base_live_20260402 CASCADE;

DROP TABLE IF EXISTS mart.hrain_v5_1_aws_test_model_input_20260402 CASCADE;
DROP TABLE IF EXISTS mart.hrain_v5_1_aws_valid_model_input_20260402 CASCADE;
DROP TABLE IF EXISTS mart.hrain_v5_1_aws_train_model_input_20260402 CASCADE;
DROP TABLE IF EXISTS mart.hrain_v5_1_aws_test_labels_20260402 CASCADE;
DROP TABLE IF EXISTS mart.hrain_v5_1_aws_valid_labels_20260402 CASCADE;
DROP TABLE IF EXISTS mart.hrain_v5_1_aws_train_labels_20260402 CASCADE;
DROP TABLE IF EXISTS mart.hrain_v5_1_aws_test_features_20260402 CASCADE;
DROP TABLE IF EXISTS mart.hrain_v5_1_aws_valid_features_20260402 CASCADE;
DROP TABLE IF EXISTS mart.hrain_v5_1_aws_train_features_20260402 CASCADE;
DROP TABLE IF EXISTS mart.hrain_v5_1_aws_test_audit_20260402 CASCADE;
DROP TABLE IF EXISTS mart.hrain_v5_1_aws_valid_audit_20260402 CASCADE;
DROP TABLE IF EXISTS mart.hrain_v5_1_aws_train_audit_20260402 CASCADE;
DROP TABLE IF EXISTS mart.hrain_v5_1_aws_snapshot_20260402 CASCADE;
DROP TABLE IF EXISTS mart.hrain_v5_1_aws_feature_base_20260402 CASCADE;
DROP TABLE IF EXISTS mart.hrain_v5_1_aws_district_index_20260402 CASCADE;
DROP TABLE IF EXISTS mart.hrain_v5_1_aws_stable_districts_20260402 CASCADE;

CREATE TABLE mart.hrain_v5_1_aws_stable_districts_20260402 AS
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

CREATE TABLE mart.hrain_v5_1_aws_district_index_20260402 AS
SELECT
    ROW_NUMBER() OVER (ORDER BY district_name) - 1 AS district_id,
    district_name
FROM mart.hrain_v5_1_aws_stable_districts_20260402
ORDER BY district_name;

CREATE UNIQUE INDEX hrain_v5_1_aws_district_index_20260402_pk
    ON mart.hrain_v5_1_aws_district_index_20260402 (district_name);

CREATE OR REPLACE VIEW mart.hrain_v5_1_aws_feature_base_live_20260402 AS
WITH observed_scope AS (
    SELECT
        'aws_hourly'::TEXT AS product_type,
        a.district_name,
        a.observed_at AS base_datetime,
        a.observed_at AS target_datetime,
        0::INTEGER AS lead_minutes,
        a.temp_c,
        a.precip_mm,
        a.humidity_pct
    FROM std.seoul_aws_district_hourly a
    INNER JOIN mart.hrain_v5_1_aws_stable_districts_20260402 s
        ON s.district_name = a.district_name
    WHERE a.observed_at >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
),
humidity_grp AS (
    SELECT
        o.product_type,
        o.district_name,
        o.base_datetime,
        o.target_datetime,
        o.lead_minutes,
        o.temp_c,
        o.precip_mm,
        o.humidity_pct,
        SUM(
            CASE
                WHEN o.humidity_pct IS NOT NULL THEN 1
                ELSE 0
            END
        ) OVER (
            PARTITION BY o.district_name
            ORDER BY o.base_datetime
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS humidity_locf_grp
    FROM observed_scope o
),
humidity_imputed AS (
    SELECT
        h.product_type,
        h.district_name,
        h.base_datetime,
        h.target_datetime,
        h.lead_minutes,
        h.temp_c,
        h.precip_mm,
        h.humidity_pct,
        CASE
            WHEN h.precip_mm IS NULL THEN TRUE
            ELSE FALSE
        END AS precip_raw_was_null,
        MAX(h.humidity_pct) OVER (
            PARTITION BY h.district_name, h.humidity_locf_grp
            ORDER BY h.base_datetime
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS humidity_locf_raw
    FROM humidity_grp h
),
lag_ready AS (
    SELECT
        i.product_type,
        i.district_name,
        i.base_datetime,
        i.target_datetime,
        i.lead_minutes,
        i.temp_c,
        i.precip_mm AS precip_mm_observed,
        COALESCE(i.precip_mm, 0.0) AS precip_mm_eff,
        i.precip_raw_was_null,
        i.humidity_pct AS humidity_pct_observed,
        i.humidity_locf_raw,
        ROUND(COALESCE(i.humidity_locf_raw, 65.0)::NUMERIC, 3)::DOUBLE PRECISION AS humidity_imputed_pct,
        CASE
            WHEN i.humidity_pct IS NULL AND i.humidity_locf_raw IS NULL THEN TRUE
            ELSE FALSE
        END AS humidity_used_default_prior,
        CASE
            WHEN i.humidity_pct IS NULL THEN TRUE
            ELSE FALSE
        END AS humidity_raw_was_null,
        LAG(COALESCE(i.precip_mm, 0.0), 1) OVER w AS lag_precip_1h_mm,
        LAG(COALESCE(i.precip_mm, 0.0), 2) OVER w AS lag_precip_2h_mm,
        LAG(i.temp_c, 3) OVER w AS lag_temp_3h_c,
        LAG(ROUND(COALESCE(i.humidity_locf_raw, 65.0)::NUMERIC, 3)::DOUBLE PRECISION, 3) OVER w AS lag_humidity_imputed_3h_pct
    FROM humidity_imputed i
    WINDOW w AS (PARTITION BY i.district_name ORDER BY i.base_datetime)
),
feature_calc AS (
    SELECT
        l.product_type,
        l.district_name,
        l.base_datetime,
        l.target_datetime,
        l.lead_minutes,
        l.precip_mm_observed,
        l.precip_mm_eff,
        l.precip_raw_was_null,
        l.temp_c,
        l.humidity_pct_observed,
        l.humidity_locf_raw,
        l.humidity_imputed_pct,
        l.humidity_used_default_prior,
        l.humidity_raw_was_null,
        CASE
            WHEN l.humidity_imputed_pct <= 0 OR l.temp_c IS NULL THEN NULL
            ELSE ROUND(
                ((
                    237.7 * (
                        LN(l.humidity_imputed_pct / 100.0) + (17.27 * l.temp_c) / (237.7 + l.temp_c)
                    )
                ) / (
                    17.27 - (
                        LN(l.humidity_imputed_pct / 100.0) + (17.27 * l.temp_c) / (237.7 + l.temp_c)
                    )
                ))::NUMERIC,
                3
            )::DOUBLE PRECISION
        END AS dew_point_c,
        ROUND(
            (
                COALESCE(l.precip_mm_eff, 0.0)
                + COALESCE(l.lag_precip_1h_mm, 0.0)
                + COALESCE(l.lag_precip_2h_mm, 0.0)
            )::NUMERIC,
            3
        )::DOUBLE PRECISION AS past_rain_3h_mm,
        CASE
            WHEN l.temp_c IS NULL THEN NULL
            ELSE ROUND(
                (l.temp_c - COALESCE(l.lag_temp_3h_c, l.temp_c))::NUMERIC,
                3
            )::DOUBLE PRECISION
        END AS temp_change_3h_c,
        CASE
            WHEN l.humidity_imputed_pct IS NULL THEN NULL
            ELSE ROUND(
                (
                    l.humidity_imputed_pct
                    - COALESCE(l.lag_humidity_imputed_3h_pct, l.humidity_imputed_pct)
                )::NUMERIC,
                3
            )::DOUBLE PRECISION
        END AS humidity_change_3h_pct,
        CASE
            WHEN l.temp_c IS NULL OR l.humidity_imputed_pct IS NULL THEN NULL
            ELSE ROUND(((l.temp_c * l.humidity_imputed_pct) / 100.0)::NUMERIC, 3)::DOUBLE PRECISION
        END AS moist_energy
    FROM lag_ready l
)
SELECT
    f.product_type,
    f.district_name,
    f.base_datetime,
    f.target_datetime,
    f.lead_minutes,
    f.precip_mm_observed,
    f.precip_mm_eff,
    f.precip_raw_was_null,
    f.temp_c,
    f.humidity_pct_observed,
    f.humidity_locf_raw,
    f.humidity_imputed_pct,
    f.humidity_used_default_prior,
    f.humidity_raw_was_null,
    f.dew_point_c,
    f.past_rain_3h_mm,
    f.temp_change_3h_c,
    f.humidity_change_3h_pct,
    f.moist_energy,
    EXTRACT(HOUR FROM f.base_datetime AT TIME ZONE 'Asia/Seoul')::INTEGER AS base_hour,
    EXTRACT(MONTH FROM f.base_datetime AT TIME ZONE 'Asia/Seoul')::INTEGER AS base_month,
    EXTRACT(DOW FROM f.base_datetime AT TIME ZONE 'Asia/Seoul')::INTEGER AS day_of_week,
    CASE
        WHEN EXTRACT(MONTH FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') BETWEEN 6 AND 9 THEN TRUE
        ELSE FALSE
    END AS is_monsoon_season_flag,
    ROUND(
        SIN(2.0 * PI() * EXTRACT(HOUR FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') / 24.0)::NUMERIC,
        6
    )::DOUBLE PRECISION AS hour_sin,
    ROUND(
        COS(2.0 * PI() * EXTRACT(HOUR FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') / 24.0)::NUMERIC,
        6
    )::DOUBLE PRECISION AS hour_cos,
    ROUND(
        SIN(2.0 * PI() * EXTRACT(MONTH FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') / 12.0)::NUMERIC,
        6
    )::DOUBLE PRECISION AS month_sin,
    ROUND(
        COS(2.0 * PI() * EXTRACT(MONTH FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') / 12.0)::NUMERIC,
        6
    )::DOUBLE PRECISION AS month_cos,
    CASE
        WHEN f.temp_c IS NOT NULL
         AND f.dew_point_c IS NOT NULL
         AND f.past_rain_3h_mm IS NOT NULL
         AND f.temp_change_3h_c IS NOT NULL
         AND f.humidity_change_3h_pct IS NOT NULL
         AND f.moist_energy IS NOT NULL
        THEN TRUE
        ELSE FALSE
    END AS is_model_input_ready,
    'std.seoul_aws_district_hourly'::TEXT AS raw_source_name,
    'aws_hourly_precip0_humidity_locf_default65_v5_1'::TEXT AS preprocessing_rule_name,
    'seoul_district_heavyrain_v5_1_aws_final'::TEXT AS data_version
FROM feature_calc f;

CREATE TABLE mart.hrain_v5_1_aws_feature_base_20260402 AS
SELECT
    product_type,
    district_name,
    base_datetime,
    target_datetime,
    lead_minutes,
    precip_mm_observed,
    precip_mm_eff,
    precip_raw_was_null,
    temp_c,
    humidity_pct_observed,
    humidity_locf_raw,
    humidity_imputed_pct,
    humidity_used_default_prior,
    humidity_raw_was_null,
    dew_point_c,
    past_rain_3h_mm,
    temp_change_3h_c,
    humidity_change_3h_pct,
    moist_energy,
    base_hour,
    base_month,
    day_of_week,
    is_monsoon_season_flag,
    hour_sin,
    hour_cos,
    month_sin,
    month_cos,
    is_model_input_ready,
    raw_source_name,
    preprocessing_rule_name,
    data_version
FROM mart.hrain_v5_1_aws_feature_base_live_20260402
WHERE base_datetime >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
  AND base_datetime <= TIMESTAMPTZ '2025-12-31 23:00:00+09';

CREATE INDEX hrain_v5_1_aws_feature_base_20260402_base_idx
    ON mart.hrain_v5_1_aws_feature_base_20260402 (base_datetime);

CREATE INDEX hrain_v5_1_aws_feature_base_20260402_district_base_idx
    ON mart.hrain_v5_1_aws_feature_base_20260402 (district_name, base_datetime);

CREATE TABLE mart.hrain_v5_1_aws_snapshot_20260402 AS
WITH label_source AS (
    SELECT
        f.product_type,
        f.district_name,
        f.base_datetime,
        f.target_datetime,
        f.lead_minutes,
        f.precip_mm_observed,
        f.precip_mm_eff,
        f.precip_raw_was_null,
        f.temp_c,
        f.humidity_pct_observed,
        f.humidity_locf_raw,
        f.humidity_imputed_pct,
        f.humidity_used_default_prior,
        f.humidity_raw_was_null,
        f.dew_point_c,
        f.past_rain_3h_mm,
        f.temp_change_3h_c,
        f.humidity_change_3h_pct,
        f.moist_energy,
        f.base_hour,
        f.base_month,
        f.day_of_week,
        f.is_monsoon_season_flag,
        f.hour_sin,
        f.hour_cos,
        f.month_sin,
        f.month_cos,
        f.is_model_input_ready,
        f.raw_source_name,
        f.preprocessing_rule_name,
        LEAD(f.precip_mm_observed, 1) OVER w AS lead_precip_1h_mm,
        LEAD(f.precip_mm_observed, 2) OVER w AS lead_precip_2h_mm,
        LEAD(f.precip_mm_observed, 3) OVER w AS lead_precip_3h_mm,
        SUM(COALESCE(f.precip_mm_observed, 0.0)) OVER (
            PARTITION BY f.district_name
            ORDER BY f.base_datetime
            ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING
        ) AS target_rain_3h_mm_raw,
        COUNT(*) OVER (
            PARTITION BY f.district_name
            ORDER BY f.base_datetime
            ROWS BETWEEN 1 FOLLOWING AND 1 FOLLOWING
        ) AS future_1h_row_count,
        COUNT(*) OVER (
            PARTITION BY f.district_name
            ORDER BY f.base_datetime
            ROWS BETWEEN 1 FOLLOWING AND 3 FOLLOWING
        ) AS future_3h_row_count
    FROM mart.hrain_v5_1_aws_feature_base_20260402 f
    WINDOW w AS (PARTITION BY f.district_name ORDER BY f.base_datetime)
),
label_enriched AS (
    SELECT
        l.product_type,
        l.district_name,
        l.base_datetime,
        l.target_datetime,
        l.lead_minutes,
        l.precip_mm_observed,
        l.precip_mm_eff,
        l.precip_raw_was_null,
        l.temp_c,
        l.humidity_pct_observed,
        l.humidity_locf_raw,
        l.humidity_imputed_pct,
        l.humidity_used_default_prior,
        l.humidity_raw_was_null,
        l.dew_point_c,
        l.past_rain_3h_mm,
        l.temp_change_3h_c,
        l.humidity_change_3h_pct,
        l.moist_energy,
        l.base_hour,
        l.base_month,
        l.day_of_week,
        l.is_monsoon_season_flag,
        l.hour_sin,
        l.hour_cos,
        l.month_sin,
        l.month_cos,
        l.is_model_input_ready,
        l.raw_source_name,
        l.preprocessing_rule_name,
        l.base_datetime + INTERVAL '3 hours' AS label_window_end,
        l.base_datetime + INTERVAL '3 hours 20 minutes' AS label_ready_at,
        CASE
            WHEN l.future_3h_row_count = 0 THEN 0
            ELSE l.future_3h_row_count
        END AS label_source_point_count,
        CASE
            WHEN l.future_1h_row_count = 0 THEN NULL
            ELSE ROUND(COALESCE(l.lead_precip_1h_mm, 0.0)::NUMERIC, 3)::DOUBLE PRECISION
        END AS target_rain_1h_mm,
        CASE
            WHEN l.future_3h_row_count = 0 THEN NULL
            ELSE ROUND(COALESCE(l.target_rain_3h_mm_raw, 0.0)::NUMERIC, 3)::DOUBLE PRECISION
        END AS target_rain_3h_mm,
        CASE
            WHEN l.base_datetime >= TIMESTAMPTZ '2020-01-01 00:00:00+09'
             AND l.base_datetime <= TIMESTAMPTZ '2023-12-31 23:00:00+09' THEN 'train'
            WHEN l.base_datetime >= TIMESTAMPTZ '2024-01-01 00:00:00+09'
             AND l.base_datetime <= TIMESTAMPTZ '2024-12-31 23:00:00+09' THEN 'valid'
            WHEN l.base_datetime >= TIMESTAMPTZ '2025-01-01 00:00:00+09'
             AND l.base_datetime <= TIMESTAMPTZ '2025-12-31 20:00:00+09' THEN 'test'
            ELSE NULL
        END AS split_type
    FROM label_source l
),
label_ruled AS (
    SELECT
        e.product_type,
        e.district_name,
        e.base_datetime,
        e.target_datetime,
        e.lead_minutes,
        e.precip_mm_observed,
        e.precip_mm_eff,
        e.precip_raw_was_null,
        e.temp_c,
        e.humidity_pct_observed,
        e.humidity_locf_raw,
        e.humidity_imputed_pct,
        e.humidity_used_default_prior,
        e.humidity_raw_was_null,
        e.dew_point_c,
        e.past_rain_3h_mm,
        e.temp_change_3h_c,
        e.humidity_change_3h_pct,
        e.moist_energy,
        e.base_hour,
        e.base_month,
        e.day_of_week,
        e.is_monsoon_season_flag,
        e.hour_sin,
        e.hour_cos,
        e.month_sin,
        e.month_cos,
        e.is_model_input_ready,
        e.label_window_end,
        e.label_ready_at,
        e.label_source_point_count,
        e.target_rain_1h_mm,
        e.target_rain_3h_mm,
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
        END AS label,
        e.split_type,
        e.raw_source_name AS label_source_name,
        '1h>=20 or 3h>=40 with lead 0..3'::TEXT AS label_rule_name,
        e.preprocessing_rule_name,
        'seoul_district_heavyrain_v5_1_aws_final'::TEXT AS data_version
    FROM label_enriched e
    WINDOW w AS (PARTITION BY e.district_name ORDER BY e.base_datetime)
)
SELECT
    product_type,
    district_name,
    base_datetime,
    target_datetime,
    lead_minutes,
    precip_mm_observed,
    precip_mm_eff,
    precip_raw_was_null,
    temp_c,
    humidity_pct_observed,
    humidity_locf_raw,
    humidity_imputed_pct,
    humidity_used_default_prior,
    humidity_raw_was_null,
    dew_point_c,
    past_rain_3h_mm,
    temp_change_3h_c,
    humidity_change_3h_pct,
    moist_energy,
    base_hour,
    base_month,
    day_of_week,
    is_monsoon_season_flag,
    hour_sin,
    hour_cos,
    month_sin,
    month_cos,
    is_model_input_ready,
    label_window_end,
    label_ready_at,
    label_source_point_count,
    target_rain_1h_mm,
    target_rain_3h_mm,
    label,
    split_type,
    label_source_name,
    label_rule_name,
    preprocessing_rule_name,
    data_version
FROM label_ruled
WHERE split_type IS NOT NULL;

CREATE INDEX hrain_v5_1_aws_snapshot_20260402_base_idx
    ON mart.hrain_v5_1_aws_snapshot_20260402 (base_datetime);

CREATE INDEX hrain_v5_1_aws_snapshot_20260402_district_base_idx
    ON mart.hrain_v5_1_aws_snapshot_20260402 (district_name, base_datetime);

CREATE TABLE mart.hrain_v5_1_aws_train_audit_20260402 AS
SELECT
    product_type,
    district_name,
    base_datetime,
    target_datetime,
    lead_minutes,
    precip_mm_observed,
    precip_mm_eff,
    precip_raw_was_null,
    temp_c,
    humidity_pct_observed,
    humidity_locf_raw,
    humidity_imputed_pct,
    humidity_used_default_prior,
    humidity_raw_was_null,
    dew_point_c,
    past_rain_3h_mm,
    temp_change_3h_c,
    humidity_change_3h_pct,
    moist_energy,
    base_hour,
    base_month,
    day_of_week,
    is_monsoon_season_flag,
    hour_sin,
    hour_cos,
    month_sin,
    month_cos,
    is_model_input_ready,
    label_window_end,
    label_ready_at,
    label_source_point_count,
    target_rain_1h_mm,
    target_rain_3h_mm,
    label,
    split_type,
    label_source_name,
    label_rule_name,
    preprocessing_rule_name,
    data_version
FROM mart.hrain_v5_1_aws_snapshot_20260402
WHERE split_type = 'train';

CREATE TABLE mart.hrain_v5_1_aws_valid_audit_20260402 AS
SELECT
    product_type,
    district_name,
    base_datetime,
    target_datetime,
    lead_minutes,
    precip_mm_observed,
    precip_mm_eff,
    precip_raw_was_null,
    temp_c,
    humidity_pct_observed,
    humidity_locf_raw,
    humidity_imputed_pct,
    humidity_used_default_prior,
    humidity_raw_was_null,
    dew_point_c,
    past_rain_3h_mm,
    temp_change_3h_c,
    humidity_change_3h_pct,
    moist_energy,
    base_hour,
    base_month,
    day_of_week,
    is_monsoon_season_flag,
    hour_sin,
    hour_cos,
    month_sin,
    month_cos,
    is_model_input_ready,
    label_window_end,
    label_ready_at,
    label_source_point_count,
    target_rain_1h_mm,
    target_rain_3h_mm,
    label,
    split_type,
    label_source_name,
    label_rule_name,
    preprocessing_rule_name,
    data_version
FROM mart.hrain_v5_1_aws_snapshot_20260402
WHERE split_type = 'valid';

CREATE TABLE mart.hrain_v5_1_aws_test_audit_20260402 AS
SELECT
    product_type,
    district_name,
    base_datetime,
    target_datetime,
    lead_minutes,
    precip_mm_observed,
    precip_mm_eff,
    precip_raw_was_null,
    temp_c,
    humidity_pct_observed,
    humidity_locf_raw,
    humidity_imputed_pct,
    humidity_used_default_prior,
    humidity_raw_was_null,
    dew_point_c,
    past_rain_3h_mm,
    temp_change_3h_c,
    humidity_change_3h_pct,
    moist_energy,
    base_hour,
    base_month,
    day_of_week,
    is_monsoon_season_flag,
    hour_sin,
    hour_cos,
    month_sin,
    month_cos,
    is_model_input_ready,
    label_window_end,
    label_ready_at,
    label_source_point_count,
    target_rain_1h_mm,
    target_rain_3h_mm,
    label,
    split_type,
    label_source_name,
    label_rule_name,
    preprocessing_rule_name,
    data_version
FROM mart.hrain_v5_1_aws_snapshot_20260402
WHERE split_type = 'test';

CREATE TABLE mart.hrain_v5_1_aws_train_features_20260402 AS
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
FROM mart.hrain_v5_1_aws_train_audit_20260402
WHERE label IS NOT NULL
  AND is_model_input_ready = TRUE;

CREATE TABLE mart.hrain_v5_1_aws_valid_features_20260402 AS
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
FROM mart.hrain_v5_1_aws_valid_audit_20260402
WHERE label IS NOT NULL
  AND is_model_input_ready = TRUE;

CREATE TABLE mart.hrain_v5_1_aws_test_features_20260402 AS
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
FROM mart.hrain_v5_1_aws_test_audit_20260402
WHERE label IS NOT NULL
  AND is_model_input_ready = TRUE;

CREATE TABLE mart.hrain_v5_1_aws_train_labels_20260402 AS
SELECT
    district_name,
    base_datetime,
    label
FROM mart.hrain_v5_1_aws_train_audit_20260402
WHERE label IS NOT NULL
  AND is_model_input_ready = TRUE;

CREATE TABLE mart.hrain_v5_1_aws_valid_labels_20260402 AS
SELECT
    district_name,
    base_datetime,
    label
FROM mart.hrain_v5_1_aws_valid_audit_20260402
WHERE label IS NOT NULL
  AND is_model_input_ready = TRUE;

CREATE TABLE mart.hrain_v5_1_aws_test_labels_20260402 AS
SELECT
    district_name,
    base_datetime,
    label
FROM mart.hrain_v5_1_aws_test_audit_20260402
WHERE label IS NOT NULL
  AND is_model_input_ready = TRUE;

CREATE TABLE mart.hrain_v5_1_aws_train_model_input_20260402 AS
SELECT
    d.district_id,
    f.district_name,
    f.base_datetime,
    EXTRACT(HOUR FROM f.base_datetime AT TIME ZONE 'Asia/Seoul')::INTEGER AS base_hour,
    EXTRACT(MONTH FROM f.base_datetime AT TIME ZONE 'Asia/Seoul')::INTEGER AS base_month,
    EXTRACT(DOW FROM f.base_datetime AT TIME ZONE 'Asia/Seoul')::INTEGER AS day_of_week,
    CASE
        WHEN EXTRACT(MONTH FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') BETWEEN 6 AND 9 THEN 1
        ELSE 0
    END AS is_monsoon_season_flag,
    ROUND(
        SIN(2.0 * PI() * EXTRACT(HOUR FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') / 24.0)::NUMERIC,
        6
    )::DOUBLE PRECISION AS hour_sin,
    ROUND(
        COS(2.0 * PI() * EXTRACT(HOUR FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') / 24.0)::NUMERIC,
        6
    )::DOUBLE PRECISION AS hour_cos,
    ROUND(
        SIN(2.0 * PI() * EXTRACT(MONTH FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') / 12.0)::NUMERIC,
        6
    )::DOUBLE PRECISION AS month_sin,
    ROUND(
        COS(2.0 * PI() * EXTRACT(MONTH FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') / 12.0)::NUMERIC,
        6
    )::DOUBLE PRECISION AS month_cos,
    f.temp_c,
    f.precip_mm,
    f.humidity_pct,
    f.dew_point_c,
    f.past_rain_3h_mm,
    f.temp_change_3h_c,
    f.humidity_change_3h_pct,
    f.moist_energy
FROM mart.hrain_v5_1_aws_train_features_20260402 f
INNER JOIN mart.hrain_v5_1_aws_district_index_20260402 d
    ON d.district_name = f.district_name;

CREATE TABLE mart.hrain_v5_1_aws_valid_model_input_20260402 AS
SELECT
    d.district_id,
    f.district_name,
    f.base_datetime,
    EXTRACT(HOUR FROM f.base_datetime AT TIME ZONE 'Asia/Seoul')::INTEGER AS base_hour,
    EXTRACT(MONTH FROM f.base_datetime AT TIME ZONE 'Asia/Seoul')::INTEGER AS base_month,
    EXTRACT(DOW FROM f.base_datetime AT TIME ZONE 'Asia/Seoul')::INTEGER AS day_of_week,
    CASE
        WHEN EXTRACT(MONTH FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') BETWEEN 6 AND 9 THEN 1
        ELSE 0
    END AS is_monsoon_season_flag,
    ROUND(
        SIN(2.0 * PI() * EXTRACT(HOUR FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') / 24.0)::NUMERIC,
        6
    )::DOUBLE PRECISION AS hour_sin,
    ROUND(
        COS(2.0 * PI() * EXTRACT(HOUR FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') / 24.0)::NUMERIC,
        6
    )::DOUBLE PRECISION AS hour_cos,
    ROUND(
        SIN(2.0 * PI() * EXTRACT(MONTH FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') / 12.0)::NUMERIC,
        6
    )::DOUBLE PRECISION AS month_sin,
    ROUND(
        COS(2.0 * PI() * EXTRACT(MONTH FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') / 12.0)::NUMERIC,
        6
    )::DOUBLE PRECISION AS month_cos,
    f.temp_c,
    f.precip_mm,
    f.humidity_pct,
    f.dew_point_c,
    f.past_rain_3h_mm,
    f.temp_change_3h_c,
    f.humidity_change_3h_pct,
    f.moist_energy
FROM mart.hrain_v5_1_aws_valid_features_20260402 f
INNER JOIN mart.hrain_v5_1_aws_district_index_20260402 d
    ON d.district_name = f.district_name;

CREATE TABLE mart.hrain_v5_1_aws_test_model_input_20260402 AS
SELECT
    d.district_id,
    f.district_name,
    f.base_datetime,
    EXTRACT(HOUR FROM f.base_datetime AT TIME ZONE 'Asia/Seoul')::INTEGER AS base_hour,
    EXTRACT(MONTH FROM f.base_datetime AT TIME ZONE 'Asia/Seoul')::INTEGER AS base_month,
    EXTRACT(DOW FROM f.base_datetime AT TIME ZONE 'Asia/Seoul')::INTEGER AS day_of_week,
    CASE
        WHEN EXTRACT(MONTH FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') BETWEEN 6 AND 9 THEN 1
        ELSE 0
    END AS is_monsoon_season_flag,
    ROUND(
        SIN(2.0 * PI() * EXTRACT(HOUR FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') / 24.0)::NUMERIC,
        6
    )::DOUBLE PRECISION AS hour_sin,
    ROUND(
        COS(2.0 * PI() * EXTRACT(HOUR FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') / 24.0)::NUMERIC,
        6
    )::DOUBLE PRECISION AS hour_cos,
    ROUND(
        SIN(2.0 * PI() * EXTRACT(MONTH FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') / 12.0)::NUMERIC,
        6
    )::DOUBLE PRECISION AS month_sin,
    ROUND(
        COS(2.0 * PI() * EXTRACT(MONTH FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') / 12.0)::NUMERIC,
        6
    )::DOUBLE PRECISION AS month_cos,
    f.temp_c,
    f.precip_mm,
    f.humidity_pct,
    f.dew_point_c,
    f.past_rain_3h_mm,
    f.temp_change_3h_c,
    f.humidity_change_3h_pct,
    f.moist_energy
FROM mart.hrain_v5_1_aws_test_features_20260402 f
INNER JOIN mart.hrain_v5_1_aws_district_index_20260402 d
    ON d.district_name = f.district_name;

CREATE OR REPLACE VIEW mart.hrain_v5_1_aws_inference_audit_latest_20260402 AS
SELECT DISTINCT ON (district_name)
    product_type,
    district_name,
    base_datetime,
    target_datetime,
    lead_minutes,
    precip_mm_observed,
    precip_mm_eff,
    precip_raw_was_null,
    temp_c,
    humidity_pct_observed,
    humidity_locf_raw,
    humidity_imputed_pct,
    humidity_used_default_prior,
    humidity_raw_was_null,
    dew_point_c,
    past_rain_3h_mm,
    temp_change_3h_c,
    humidity_change_3h_pct,
    moist_energy,
    base_hour,
    base_month,
    day_of_week,
    is_monsoon_season_flag,
    hour_sin,
    hour_cos,
    month_sin,
    month_cos,
    is_model_input_ready,
    raw_source_name,
    preprocessing_rule_name,
    data_version
FROM mart.hrain_v5_1_aws_feature_base_live_20260402
WHERE is_model_input_ready = TRUE
ORDER BY district_name, base_datetime DESC;

CREATE OR REPLACE VIEW mart.hrain_v5_1_aws_inference_features_latest_20260402 AS
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
FROM mart.hrain_v5_1_aws_inference_audit_latest_20260402;

CREATE OR REPLACE VIEW mart.hrain_v5_1_aws_inference_model_input_latest_20260402 AS
SELECT
    d.district_id,
    f.district_name,
    f.base_datetime,
    EXTRACT(HOUR FROM f.base_datetime AT TIME ZONE 'Asia/Seoul')::INTEGER AS base_hour,
    EXTRACT(MONTH FROM f.base_datetime AT TIME ZONE 'Asia/Seoul')::INTEGER AS base_month,
    EXTRACT(DOW FROM f.base_datetime AT TIME ZONE 'Asia/Seoul')::INTEGER AS day_of_week,
    CASE
        WHEN EXTRACT(MONTH FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') BETWEEN 6 AND 9 THEN 1
        ELSE 0
    END AS is_monsoon_season_flag,
    ROUND(
        SIN(2.0 * PI() * EXTRACT(HOUR FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') / 24.0)::NUMERIC,
        6
    )::DOUBLE PRECISION AS hour_sin,
    ROUND(
        COS(2.0 * PI() * EXTRACT(HOUR FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') / 24.0)::NUMERIC,
        6
    )::DOUBLE PRECISION AS hour_cos,
    ROUND(
        SIN(2.0 * PI() * EXTRACT(MONTH FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') / 12.0)::NUMERIC,
        6
    )::DOUBLE PRECISION AS month_sin,
    ROUND(
        COS(2.0 * PI() * EXTRACT(MONTH FROM f.base_datetime AT TIME ZONE 'Asia/Seoul') / 12.0)::NUMERIC,
        6
    )::DOUBLE PRECISION AS month_cos,
    f.temp_c,
    f.precip_mm,
    f.humidity_pct,
    f.dew_point_c,
    f.past_rain_3h_mm,
    f.temp_change_3h_c,
    f.humidity_change_3h_pct,
    f.moist_energy
FROM mart.hrain_v5_1_aws_inference_features_latest_20260402 f
INNER JOIN mart.hrain_v5_1_aws_district_index_20260402 d
    ON d.district_name = f.district_name;

ANALYZE mart.hrain_v5_1_aws_stable_districts_20260402;
ANALYZE mart.hrain_v5_1_aws_district_index_20260402;
ANALYZE mart.hrain_v5_1_aws_feature_base_20260402;
ANALYZE mart.hrain_v5_1_aws_snapshot_20260402;
ANALYZE mart.hrain_v5_1_aws_train_audit_20260402;
ANALYZE mart.hrain_v5_1_aws_valid_audit_20260402;
ANALYZE mart.hrain_v5_1_aws_test_audit_20260402;
ANALYZE mart.hrain_v5_1_aws_train_features_20260402;
ANALYZE mart.hrain_v5_1_aws_valid_features_20260402;
ANALYZE mart.hrain_v5_1_aws_test_features_20260402;
ANALYZE mart.hrain_v5_1_aws_train_labels_20260402;
ANALYZE mart.hrain_v5_1_aws_valid_labels_20260402;
ANALYZE mart.hrain_v5_1_aws_test_labels_20260402;
ANALYZE mart.hrain_v5_1_aws_train_model_input_20260402;
ANALYZE mart.hrain_v5_1_aws_valid_model_input_20260402;
ANALYZE mart.hrain_v5_1_aws_test_model_input_20260402;

COMMIT;
