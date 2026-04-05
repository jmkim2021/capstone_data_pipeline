CREATE SCHEMA IF NOT EXISTS ref;

CREATE TABLE IF NOT EXISTS raw.seoul_rain_gauge_station_raw (
    id BIGSERIAL PRIMARY KEY,
    source_file_name TEXT NOT NULL,
    excel_row_number INTEGER NOT NULL,
    station_code INTEGER,
    effective_start_date DATE,
    effective_end_date DATE,
    station_name TEXT,
    station_address TEXT,
    managing_office TEXT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    site_altitude_m DOUBLE PRECISION,
    barometer_height_m DOUBLE PRECISION,
    thermometer_height_m DOUBLE PRECISION,
    anemometer_height_m DOUBLE PRECISION,
    raingauge_height_m DOUBLE PRECISION,
    source_row_hash TEXT NOT NULL,
    row_json JSONB NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_raw_seoul_rain_gauge_station_raw_source
    ON raw.seoul_rain_gauge_station_raw (source_file_name, excel_row_number);

CREATE INDEX IF NOT EXISTS idx_raw_seoul_rain_gauge_station_raw_hash
    ON raw.seoul_rain_gauge_station_raw (source_row_hash);

CREATE TABLE IF NOT EXISTS ref.seoul_rain_gauge_station_history (
    id BIGSERIAL PRIMARY KEY,
    station_code INTEGER NOT NULL,
    effective_start_date DATE,
    effective_end_date DATE,
    station_name TEXT NOT NULL,
    station_address TEXT,
    managing_office TEXT,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    site_altitude_m DOUBLE PRECISION,
    barometer_height_m DOUBLE PRECISION,
    thermometer_height_m DOUBLE PRECISION,
    anemometer_height_m DOUBLE PRECISION,
    raingauge_height_m DOUBLE PRECISION,
    geom geometry(Point, 4326) NOT NULL,
    is_current BOOLEAN NOT NULL DEFAULT FALSE,
    source_file_name TEXT NOT NULL,
    excel_row_number INTEGER NOT NULL,
    source_row_hash TEXT NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_ref_seoul_rain_gauge_station_history_hash
    ON ref.seoul_rain_gauge_station_history (source_row_hash);

CREATE INDEX IF NOT EXISTS idx_ref_seoul_rain_gauge_station_history_station
    ON ref.seoul_rain_gauge_station_history (station_code, effective_start_date, effective_end_date);

CREATE INDEX IF NOT EXISTS idx_ref_seoul_rain_gauge_station_history_current
    ON ref.seoul_rain_gauge_station_history (is_current);

CREATE INDEX IF NOT EXISTS idx_ref_seoul_rain_gauge_station_history_geom
    ON ref.seoul_rain_gauge_station_history
    USING GIST (geom);

CREATE OR REPLACE VIEW ref.seoul_rain_gauge_station_current AS
SELECT DISTINCT ON (station_code)
    station_code,
    effective_start_date,
    effective_end_date,
    station_name,
    station_address,
    managing_office,
    latitude,
    longitude,
    site_altitude_m,
    barometer_height_m,
    thermometer_height_m,
    anemometer_height_m,
    raingauge_height_m,
    geom,
    is_current,
    source_file_name,
    excel_row_number,
    source_row_hash,
    loaded_at,
    created_at,
    updated_at
FROM ref.seoul_rain_gauge_station_history
ORDER BY
    station_code,
    (effective_end_date IS NULL) DESC,
    effective_start_date DESC NULLS LAST,
    excel_row_number DESC;
