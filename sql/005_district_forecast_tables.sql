BEGIN;

CREATE SCHEMA IF NOT EXISTS mart;

CREATE TABLE IF NOT EXISTS mart.seoul_district_ultra_fcst (
    base_datetime TIMESTAMPTZ NOT NULL,
    forecast_datetime TIMESTAMPTZ NOT NULL,
    lead_minutes INTEGER NOT NULL,
    district_name TEXT NOT NULL,
    forecast_temp_c DOUBLE PRECISION,
    forecast_humidity_pct DOUBLE PRECISION,
    forecast_precip_mm_num DOUBLE PRECISION,
    forecast_wind_speed_ms DOUBLE PRECISION,
    forecast_sky_code TEXT,
    forecast_precip_type_code TEXT,
    source_grid_count INTEGER NOT NULL,
    weight_sum NUMERIC(12, 6) NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (base_datetime, forecast_datetime, district_name)
);

CREATE INDEX IF NOT EXISTS idx_seoul_district_ultra_fcst_requested_at
    ON mart.seoul_district_ultra_fcst (requested_at);

CREATE TABLE IF NOT EXISTS mart.seoul_district_short_fcst (
    base_datetime TIMESTAMPTZ NOT NULL,
    forecast_datetime TIMESTAMPTZ NOT NULL,
    lead_hours INTEGER NOT NULL,
    district_name TEXT NOT NULL,
    forecast_temp_c DOUBLE PRECISION,
    forecast_humidity_pct DOUBLE PRECISION,
    forecast_pop_pct DOUBLE PRECISION,
    forecast_precip_mm_num DOUBLE PRECISION,
    forecast_wind_speed_ms DOUBLE PRECISION,
    forecast_sky_code TEXT,
    forecast_precip_type_code TEXT,
    source_grid_count INTEGER NOT NULL,
    weight_sum NUMERIC(12, 6) NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (base_datetime, forecast_datetime, district_name)
);

CREATE INDEX IF NOT EXISTS idx_seoul_district_short_fcst_requested_at
    ON mart.seoul_district_short_fcst (requested_at);

COMMIT;
