BEGIN;

CREATE SCHEMA IF NOT EXISTS mart;

CREATE OR REPLACE VIEW mart.seoul_district_weather_timeline AS
SELECT
    'ultra_now'::TEXT AS product_type,
    district_name,
    base_datetime,
    base_datetime AS target_datetime,
    0::INTEGER AS lead_minutes,
    rain_1h_mm AS precip_mm,
    temp_c,
    humidity_pct,
    NULL::DOUBLE PRECISION AS pop_pct,
    wind_speed_ms,
    NULL::TEXT AS sky_code,
    precip_type_code,
    requested_at
FROM mart.seoul_district_ultra_now

UNION ALL

SELECT
    'ultra_fcst'::TEXT AS product_type,
    district_name,
    base_datetime,
    forecast_datetime AS target_datetime,
    lead_minutes,
    forecast_precip_mm_num AS precip_mm,
    forecast_temp_c AS temp_c,
    forecast_humidity_pct AS humidity_pct,
    NULL::DOUBLE PRECISION AS pop_pct,
    forecast_wind_speed_ms AS wind_speed_ms,
    forecast_sky_code AS sky_code,
    forecast_precip_type_code AS precip_type_code,
    requested_at
FROM mart.seoul_district_ultra_fcst

UNION ALL

SELECT
    'short_fcst'::TEXT AS product_type,
    district_name,
    base_datetime,
    forecast_datetime AS target_datetime,
    lead_hours * 60 AS lead_minutes,
    forecast_precip_mm_num AS precip_mm,
    forecast_temp_c AS temp_c,
    forecast_humidity_pct AS humidity_pct,
    forecast_pop_pct AS pop_pct,
    forecast_wind_speed_ms AS wind_speed_ms,
    forecast_sky_code AS sky_code,
    forecast_precip_type_code AS precip_type_code,
    requested_at
FROM mart.seoul_district_short_fcst
;

COMMIT;
