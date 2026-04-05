BEGIN;

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS std;
CREATE SCHEMA IF NOT EXISTS mart;
CREATE SCHEMA IF NOT EXISTS meta;

CREATE TABLE IF NOT EXISTS raw.kma_ultra_now_raw (
    requested_at TIMESTAMPTZ NOT NULL,
    base_date TEXT NOT NULL,
    base_time TEXT NOT NULL,
    nx INTEGER NOT NULL,
    ny INTEGER NOT NULL,
    category TEXT NOT NULL,
    obsr_value TEXT,
    response_json JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS raw.kma_ultra_fcst_raw (
    requested_at TIMESTAMPTZ NOT NULL,
    base_date TEXT NOT NULL,
    base_time TEXT NOT NULL,
    fcst_date TEXT NOT NULL,
    fcst_time TEXT NOT NULL,
    nx INTEGER NOT NULL,
    ny INTEGER NOT NULL,
    category TEXT NOT NULL,
    fcst_value TEXT,
    response_json JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS raw.kma_short_fcst_raw (
    requested_at TIMESTAMPTZ NOT NULL,
    base_date TEXT NOT NULL,
    base_time TEXT NOT NULL,
    fcst_date TEXT NOT NULL,
    fcst_time TEXT NOT NULL,
    nx INTEGER NOT NULL,
    ny INTEGER NOT NULL,
    category TEXT NOT NULL,
    fcst_value TEXT,
    response_json JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS std.kma_ultra_now_std (
    base_datetime TIMESTAMPTZ NOT NULL,
    nx INTEGER NOT NULL,
    ny INTEGER NOT NULL,
    rain_1h_text TEXT,
    rain_1h_mm DOUBLE PRECISION,
    rain_1h_parse_type TEXT,
    temp_c DOUBLE PRECISION,
    humidity_pct DOUBLE PRECISION,
    wind_speed_ms DOUBLE PRECISION,
    wind_dir_deg DOUBLE PRECISION,
    precip_type_code TEXT,
    requested_at TIMESTAMPTZ,
    raw_batch_time TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (base_datetime, nx, ny)
);

CREATE TABLE IF NOT EXISTS std.kma_ultra_fcst_std (
    base_datetime TIMESTAMPTZ NOT NULL,
    forecast_datetime TIMESTAMPTZ NOT NULL,
    lead_minutes INTEGER NOT NULL,
    nx INTEGER NOT NULL,
    ny INTEGER NOT NULL,
    forecast_temp_c DOUBLE PRECISION,
    forecast_humidity_pct DOUBLE PRECISION,
    forecast_sky_code TEXT,
    forecast_precip_type_code TEXT,
    forecast_precip_mm_text TEXT,
    forecast_precip_mm_num DOUBLE PRECISION,
    forecast_precip_parse_type TEXT,
    forecast_wind_speed_ms DOUBLE PRECISION,
    requested_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (base_datetime, forecast_datetime, nx, ny)
);

CREATE TABLE IF NOT EXISTS std.kma_short_fcst_std (
    base_datetime TIMESTAMPTZ NOT NULL,
    forecast_datetime TIMESTAMPTZ NOT NULL,
    lead_hours INTEGER NOT NULL,
    nx INTEGER NOT NULL,
    ny INTEGER NOT NULL,
    forecast_temp_c DOUBLE PRECISION,
    forecast_humidity_pct DOUBLE PRECISION,
    forecast_pop_pct DOUBLE PRECISION,
    forecast_precip_mm_text TEXT,
    forecast_precip_mm_num DOUBLE PRECISION,
    forecast_precip_parse_type TEXT,
    forecast_sky_code TEXT,
    forecast_precip_type_code TEXT,
    forecast_wind_speed_ms DOUBLE PRECISION,
    requested_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (base_datetime, forecast_datetime, nx, ny)
);

COMMIT;
