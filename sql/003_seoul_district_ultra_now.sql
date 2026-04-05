BEGIN;

CREATE SCHEMA IF NOT EXISTS mart;

CREATE TABLE IF NOT EXISTS mart.seoul_district_ultra_now (
    base_datetime TIMESTAMPTZ NOT NULL,
    district_name TEXT NOT NULL,
    rain_1h_mm DOUBLE PRECISION,
    temp_c DOUBLE PRECISION,
    humidity_pct DOUBLE PRECISION,
    wind_speed_ms DOUBLE PRECISION,
    wind_dir_deg DOUBLE PRECISION,
    precip_type_code TEXT,
    source_grid_count INTEGER NOT NULL,
    weight_sum NUMERIC(12, 6) NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL,
    raw_batch_time TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (base_datetime, district_name)
);

CREATE INDEX IF NOT EXISTS idx_seoul_district_ultra_now_requested_at
    ON mart.seoul_district_ultra_now (requested_at);

COMMIT;
