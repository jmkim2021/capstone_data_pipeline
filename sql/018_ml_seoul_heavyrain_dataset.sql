BEGIN;

CREATE SCHEMA IF NOT EXISTS ml;

DROP TABLE IF EXISTS ml.seoul_heavyrain_test;
DROP TABLE IF EXISTS ml.seoul_heavyrain_valid;
DROP TABLE IF EXISTS ml.seoul_heavyrain_train;
DROP TABLE IF EXISTS ml.seoul_heavyrain_dataset_all;

CREATE TABLE ml.seoul_heavyrain_dataset_all AS
WITH params AS (
    SELECT
        TIMESTAMPTZ '2020-01-01 00:00:00+09' AS train_start_at,
        TIMESTAMPTZ '2024-01-01 00:00:00+09' AS valid_start_at,
        TIMESTAMPTZ '2025-01-01 00:00:00+09' AS test_start_at,
        TIMESTAMPTZ '2026-01-01 00:00:00+09' AS dataset_end_at,
        20.0::DOUBLE PRECISION AS heavy_rain_1h_threshold_mm,
        50.0::DOUBLE PRECISION AS heavy_rain_3h_threshold_mm,
        'future_1h>=20mm OR future_3h>=50mm using mart.seoul_aws_district_timeline'::TEXT AS target_definition,
        'seoul_heavyrain_aws_v3_20260331'::TEXT AS dataset_version
),
base_rows AS (
    SELECT
        b.district_name,
        b.observed_at AS base_datetime,
        b.station_code AS aws_station_code,
        b.precip_mm AS aws_precip_mm,
        b.temp_c AS aws_temp_c,
        b.humidity_pct AS aws_humidity_pct,
        b.wind_speed_ms AS aws_wind_speed_ms,
        b.wind_dir_deg AS aws_wind_dir_deg,
        b.local_pressure_hpa AS aws_local_pressure_hpa,
        b.sea_level_pressure_hpa AS aws_sea_level_pressure_hpa,
        b.solar_radiation_mj_m2 AS aws_solar_radiation_mj_m2,
        b.sunshine_hr AS aws_sunshine_hr,
        l1.precip_mm AS lag_rain_1h_mm,
        l2.precip_mm AS lag_rain_2h_mm,
        l3.precip_mm AS lag_rain_3h_mm,
        l6.precip_mm AS lag_rain_6h_mm,
        l12.precip_mm AS lag_rain_12h_mm,
        l24.precip_mm AS lag_rain_24h_mm,
        l1.temp_c AS lag_temp_1h_c,
        l1.humidity_pct AS lag_humidity_1h_pct,
        l1.wind_speed_ms AS lag_wind_speed_1h_ms,
        f1.precip_mm AS target_rain_1h_mm,
        (COALESCE(f1.precip_mm, 0.0) + COALESCE(f2.precip_mm, 0.0) + COALESCE(f3.precip_mm, 0.0))::DOUBLE PRECISION AS target_rain_3h_mm
    FROM mart.seoul_aws_district_timeline b
    CROSS JOIN params p
    LEFT JOIN mart.seoul_aws_district_timeline l1
        ON l1.district_name = b.district_name
       AND l1.observed_at = b.observed_at - INTERVAL '1 hour'
    LEFT JOIN mart.seoul_aws_district_timeline l2
        ON l2.district_name = b.district_name
       AND l2.observed_at = b.observed_at - INTERVAL '2 hour'
    LEFT JOIN mart.seoul_aws_district_timeline l3
        ON l3.district_name = b.district_name
       AND l3.observed_at = b.observed_at - INTERVAL '3 hour'
    LEFT JOIN mart.seoul_aws_district_timeline l6
        ON l6.district_name = b.district_name
       AND l6.observed_at = b.observed_at - INTERVAL '6 hour'
    LEFT JOIN mart.seoul_aws_district_timeline l12
        ON l12.district_name = b.district_name
       AND l12.observed_at = b.observed_at - INTERVAL '12 hour'
    LEFT JOIN mart.seoul_aws_district_timeline l24
        ON l24.district_name = b.district_name
       AND l24.observed_at = b.observed_at - INTERVAL '24 hour'
    JOIN mart.seoul_aws_district_timeline f1
        ON f1.district_name = b.district_name
       AND f1.observed_at = b.observed_at + INTERVAL '1 hour'
    JOIN mart.seoul_aws_district_timeline f2
        ON f2.district_name = b.district_name
       AND f2.observed_at = b.observed_at + INTERVAL '2 hour'
    JOIN mart.seoul_aws_district_timeline f3
        ON f3.district_name = b.district_name
       AND f3.observed_at = b.observed_at + INTERVAL '3 hour'
    WHERE b.observed_at >= p.train_start_at
      AND b.observed_at < p.dataset_end_at - INTERVAL '3 hour'
      AND f1.precip_mm IS NOT NULL
      AND f2.precip_mm IS NOT NULL
      AND f3.precip_mm IS NOT NULL
),
feature_enriched AS (
    SELECT
        b.base_datetime,
        b.district_name,
        b.aws_station_code,
        EXTRACT(YEAR FROM b.base_datetime)::INTEGER AS base_year,
        EXTRACT(MONTH FROM b.base_datetime)::INTEGER AS base_month,
        EXTRACT(DAY FROM b.base_datetime)::INTEGER AS base_day,
        EXTRACT(HOUR FROM b.base_datetime)::INTEGER AS base_hour,
        EXTRACT(DOW FROM b.base_datetime)::INTEGER AS day_of_week,
        EXTRACT(DOY FROM b.base_datetime)::INTEGER AS day_of_year,
        CASE
            WHEN EXTRACT(DOW FROM b.base_datetime) IN (0, 6) THEN 1
            ELSE 0
        END AS is_weekend_flag,
        CASE
            WHEN EXTRACT(MONTH FROM b.base_datetime) BETWEEN 6 AND 9 THEN 1
            ELSE 0
        END AS is_monsoon_season_flag,
        ROUND(SIN(2.0 * PI() * EXTRACT(HOUR FROM b.base_datetime) / 24.0)::NUMERIC, 6)::DOUBLE PRECISION AS hour_sin,
        ROUND(COS(2.0 * PI() * EXTRACT(HOUR FROM b.base_datetime) / 24.0)::NUMERIC, 6)::DOUBLE PRECISION AS hour_cos,
        ROUND(SIN(2.0 * PI() * EXTRACT(MONTH FROM b.base_datetime) / 12.0)::NUMERIC, 6)::DOUBLE PRECISION AS month_sin,
        ROUND(COS(2.0 * PI() * EXTRACT(MONTH FROM b.base_datetime) / 12.0)::NUMERIC, 6)::DOUBLE PRECISION AS month_cos,
        b.aws_precip_mm,
        b.aws_temp_c,
        b.aws_humidity_pct,
        b.aws_wind_speed_ms,
        b.aws_wind_dir_deg,
        b.aws_local_pressure_hpa,
        b.aws_sea_level_pressure_hpa,
        b.aws_solar_radiation_mj_m2,
        b.aws_sunshine_hr,
        b.lag_rain_1h_mm,
        b.lag_rain_2h_mm,
        b.lag_rain_3h_mm,
        b.lag_rain_6h_mm,
        b.lag_rain_12h_mm,
        b.lag_rain_24h_mm,
        CASE
            WHEN b.aws_precip_mm IS NULL OR b.lag_rain_1h_mm IS NULL OR b.lag_rain_2h_mm IS NULL THEN NULL
            ELSE (COALESCE(b.aws_precip_mm, 0.0) + COALESCE(b.lag_rain_1h_mm, 0.0) + COALESCE(b.lag_rain_2h_mm, 0.0))::DOUBLE PRECISION
        END AS past_rain_3h_mm,
        CASE
            WHEN b.aws_precip_mm IS NULL OR b.lag_rain_1h_mm IS NULL THEN NULL
            ELSE (b.aws_precip_mm - b.lag_rain_1h_mm)::DOUBLE PRECISION
        END AS rain_delta_1h_mm,
        b.lag_temp_1h_c,
        CASE
            WHEN b.aws_temp_c IS NULL OR b.lag_temp_1h_c IS NULL THEN NULL
            ELSE (b.aws_temp_c - b.lag_temp_1h_c)::DOUBLE PRECISION
        END AS temp_delta_1h_c,
        b.lag_humidity_1h_pct,
        CASE
            WHEN b.aws_humidity_pct IS NULL OR b.lag_humidity_1h_pct IS NULL THEN NULL
            ELSE (b.aws_humidity_pct - b.lag_humidity_1h_pct)::DOUBLE PRECISION
        END AS humidity_delta_1h_pct,
        b.lag_wind_speed_1h_ms,
        CASE
            WHEN b.aws_wind_speed_ms IS NULL OR b.lag_wind_speed_1h_ms IS NULL THEN NULL
            ELSE (b.aws_wind_speed_ms - b.lag_wind_speed_1h_ms)::DOUBLE PRECISION
        END AS wind_speed_delta_1h_ms,
        b.target_rain_1h_mm,
        b.target_rain_3h_mm
    FROM base_rows b
)
SELECT
    f.base_datetime,
    f.district_name,
    f.aws_station_code,
    f.base_year,
    f.base_month,
    f.base_day,
    f.base_hour,
    f.day_of_week,
    f.day_of_year,
    f.is_weekend_flag,
    f.is_monsoon_season_flag,
    f.hour_sin,
    f.hour_cos,
    f.month_sin,
    f.month_cos,
    f.aws_precip_mm,
    f.aws_temp_c,
    f.aws_humidity_pct,
    f.aws_wind_speed_ms,
    f.aws_wind_dir_deg,
    f.aws_local_pressure_hpa,
    f.aws_sea_level_pressure_hpa,
    f.aws_solar_radiation_mj_m2,
    f.aws_sunshine_hr,
    f.lag_rain_1h_mm,
    f.lag_rain_2h_mm,
    f.lag_rain_3h_mm,
    f.lag_rain_6h_mm,
    f.lag_rain_12h_mm,
    f.lag_rain_24h_mm,
    f.past_rain_3h_mm,
    f.rain_delta_1h_mm,
    f.lag_temp_1h_c,
    f.temp_delta_1h_c,
    f.lag_humidity_1h_pct,
    f.humidity_delta_1h_pct,
    f.lag_wind_speed_1h_ms,
    f.wind_speed_delta_1h_ms,
    f.target_rain_1h_mm,
    f.target_rain_3h_mm,
    CASE
        WHEN f.target_rain_1h_mm >= p.heavy_rain_1h_threshold_mm
          OR f.target_rain_3h_mm >= p.heavy_rain_3h_threshold_mm
        THEN 1
        ELSE 0
    END AS target_heavy_rain_flag,
    p.target_definition,
    CASE
        WHEN f.base_datetime < p.valid_start_at THEN 'train'
        WHEN f.base_datetime < p.test_start_at THEN 'valid'
        ELSE 'test'
    END AS split_type,
    p.dataset_version,
    NOW() AS created_at
FROM feature_enriched f
CROSS JOIN params p;

ALTER TABLE ml.seoul_heavyrain_dataset_all
    ADD PRIMARY KEY (district_name, base_datetime);

CREATE INDEX idx_ml_seoul_heavyrain_dataset_all_split_base
    ON ml.seoul_heavyrain_dataset_all (split_type, base_datetime, district_name);

CREATE INDEX idx_ml_seoul_heavyrain_dataset_all_target
    ON ml.seoul_heavyrain_dataset_all (target_heavy_rain_flag, base_datetime);

CREATE TABLE ml.seoul_heavyrain_train AS
SELECT *
FROM ml.seoul_heavyrain_dataset_all
WHERE split_type = 'train';

ALTER TABLE ml.seoul_heavyrain_train
    ADD PRIMARY KEY (district_name, base_datetime);

CREATE INDEX idx_ml_seoul_heavyrain_train_target
    ON ml.seoul_heavyrain_train (target_heavy_rain_flag, base_datetime);

CREATE TABLE ml.seoul_heavyrain_valid AS
SELECT *
FROM ml.seoul_heavyrain_dataset_all
WHERE split_type = 'valid';

ALTER TABLE ml.seoul_heavyrain_valid
    ADD PRIMARY KEY (district_name, base_datetime);

CREATE INDEX idx_ml_seoul_heavyrain_valid_target
    ON ml.seoul_heavyrain_valid (target_heavy_rain_flag, base_datetime);

CREATE TABLE ml.seoul_heavyrain_test AS
SELECT *
FROM ml.seoul_heavyrain_dataset_all
WHERE split_type = 'test';

ALTER TABLE ml.seoul_heavyrain_test
    ADD PRIMARY KEY (district_name, base_datetime);

CREATE INDEX idx_ml_seoul_heavyrain_test_target
    ON ml.seoul_heavyrain_test (target_heavy_rain_flag, base_datetime);

ANALYZE ml.seoul_heavyrain_dataset_all;
ANALYZE ml.seoul_heavyrain_train;
ANALYZE ml.seoul_heavyrain_valid;
ANALYZE ml.seoul_heavyrain_test;

COMMIT;
