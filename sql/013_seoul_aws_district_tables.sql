CREATE TABLE IF NOT EXISTS raw.seoul_aws_district_raw (
    id BIGSERIAL PRIMARY KEY,
    district_name TEXT NOT NULL,
    station_code INTEGER NOT NULL,
    observed_at TIMESTAMPTZ NOT NULL,
    source_zip_name TEXT NOT NULL,
    source_csv_name TEXT NOT NULL,
    source_row_number INTEGER NOT NULL,
    row_json JSONB NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_raw_seoul_aws_district_raw_obs
    ON raw.seoul_aws_district_raw (district_name, observed_at DESC);

CREATE TABLE IF NOT EXISTS std.seoul_aws_district_hourly (
    district_name TEXT NOT NULL,
    station_code INTEGER NOT NULL,
    observed_at TIMESTAMPTZ NOT NULL,
    temp_c DOUBLE PRECISION,
    wind_dir_deg DOUBLE PRECISION,
    wind_speed_ms DOUBLE PRECISION,
    precip_mm DOUBLE PRECISION,
    local_pressure_hpa DOUBLE PRECISION,
    sea_level_pressure_hpa DOUBLE PRECISION,
    humidity_pct DOUBLE PRECISION,
    solar_radiation_mj_m2 DOUBLE PRECISION,
    sunshine_hr DOUBLE PRECISION,
    source_zip_name TEXT NOT NULL,
    source_csv_name TEXT NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (district_name, observed_at)
);

CREATE INDEX IF NOT EXISTS idx_std_seoul_aws_district_hourly_station
    ON std.seoul_aws_district_hourly (station_code, observed_at DESC);

CREATE OR REPLACE VIEW mart.seoul_aws_district_latest AS
SELECT DISTINCT ON (district_name)
    district_name,
    station_code,
    observed_at,
    temp_c,
    wind_dir_deg,
    wind_speed_ms,
    precip_mm,
    local_pressure_hpa,
    sea_level_pressure_hpa,
    humidity_pct,
    solar_radiation_mj_m2,
    sunshine_hr
FROM std.seoul_aws_district_hourly
ORDER BY district_name, observed_at DESC;
