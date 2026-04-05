CREATE TABLE IF NOT EXISTS raw.seoul_rainfall_raw (
    id BIGSERIAL PRIMARY KEY,
    requested_at TIMESTAMPTZ NOT NULL,
    observed_at TIMESTAMPTZ NOT NULL,
    station_code INTEGER NOT NULL,
    response_json JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_raw_seoul_rainfall_raw_observed
    ON raw.seoul_rainfall_raw (observed_at DESC, station_code);

CREATE TABLE IF NOT EXISTS std.seoul_rainfall_std (
    observed_at TIMESTAMPTZ NOT NULL,
    station_code INTEGER NOT NULL,
    station_name TEXT NOT NULL,
    district_code INTEGER,
    district_name TEXT,
    rain_10m_mm DOUBLE PRECISION,
    requested_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (observed_at, station_code)
);

CREATE INDEX IF NOT EXISTS idx_std_seoul_rainfall_std_district
    ON std.seoul_rainfall_std (district_name, observed_at DESC);

CREATE TABLE IF NOT EXISTS mart.seoul_rainfall_district_latest (
    observed_at TIMESTAMPTZ NOT NULL,
    district_name TEXT NOT NULL,
    station_count INTEGER NOT NULL,
    avg_rain_10m_mm DOUBLE PRECISION,
    max_rain_10m_mm DOUBLE PRECISION,
    requested_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (observed_at, district_name)
);

CREATE TABLE IF NOT EXISTS raw.seoul_river_stage_raw (
    id BIGSERIAL PRIMARY KEY,
    requested_at TIMESTAMPTZ NOT NULL,
    observed_at TIMESTAMPTZ NOT NULL,
    station_code TEXT NOT NULL,
    response_json JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_raw_seoul_river_stage_raw_observed
    ON raw.seoul_river_stage_raw (observed_at DESC, station_code);

CREATE TABLE IF NOT EXISTS std.seoul_river_stage_std (
    observed_at TIMESTAMPTZ NOT NULL,
    station_code TEXT NOT NULL,
    station_name TEXT NOT NULL,
    river_name TEXT,
    district_code TEXT,
    district_name TEXT,
    water_level_m DOUBLE PRECISION,
    embankment_height_m DOUBLE PRECISION,
    plan_flood_level_m DOUBLE PRECISION,
    riverbed_height_m DOUBLE PRECISION,
    control_level_m DOUBLE PRECISION,
    requested_at TIMESTAMPTZ NOT NULL,
    server_stored_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (observed_at, station_code)
);

CREATE INDEX IF NOT EXISTS idx_std_seoul_river_stage_std_district
    ON std.seoul_river_stage_std (district_name, observed_at DESC);

CREATE TABLE IF NOT EXISTS mart.seoul_river_stage_district_latest (
    observed_minute TIMESTAMPTZ NOT NULL,
    district_name TEXT NOT NULL,
    station_count INTEGER NOT NULL,
    avg_water_level_m DOUBLE PRECISION,
    max_water_level_m DOUBLE PRECISION,
    max_control_level_m DOUBLE PRECISION,
    requested_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (observed_minute, district_name)
);

CREATE TABLE IF NOT EXISTS raw.kma_hsr_request_raw (
    id BIGSERIAL PRIMARY KEY,
    requested_at TIMESTAMPTZ NOT NULL,
    base_datetime TIMESTAMPTZ NOT NULL,
    http_status INTEGER,
    is_success BOOLEAN NOT NULL,
    error_message TEXT,
    response_text TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_raw_kma_hsr_request_raw_base
    ON raw.kma_hsr_request_raw (base_datetime DESC);

CREATE TABLE IF NOT EXISTS std.kma_hsr_file_inventory_std (
    base_datetime TIMESTAMPTZ NOT NULL,
    file_name TEXT NOT NULL,
    file_url TEXT,
    requested_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (base_datetime, file_name)
);

-- 운영용 전체 목록은 sql/028_operational_reliability.sql 이 덮어쓴다(HSR area·건설·생활인구 등).
CREATE OR REPLACE VIEW mart.external_source_collection_status AS
SELECT 'seoul_rainfall_raw' AS source_name, COUNT(*) AS row_count, MAX(requested_at) AS latest_requested_at
FROM raw.seoul_rainfall_raw
UNION ALL
SELECT 'seoul_rainfall_std' AS source_name, COUNT(*) AS row_count, MAX(requested_at) AS latest_requested_at
FROM std.seoul_rainfall_std
UNION ALL
SELECT 'seoul_river_stage_raw' AS source_name, COUNT(*) AS row_count, MAX(requested_at) AS latest_requested_at
FROM raw.seoul_river_stage_raw
UNION ALL
SELECT 'seoul_river_stage_std' AS source_name, COUNT(*) AS row_count, MAX(requested_at) AS latest_requested_at
FROM std.seoul_river_stage_std
UNION ALL
SELECT 'kma_hsr_request_raw' AS source_name, COUNT(*) AS row_count, MAX(requested_at) AS latest_requested_at
FROM raw.kma_hsr_request_raw
UNION ALL
SELECT 'kma_hsr_file_inventory_std' AS source_name, COUNT(*) AS row_count, MAX(requested_at) AS latest_requested_at
FROM std.kma_hsr_file_inventory_std
UNION ALL
SELECT 'seoul_construction_progress_raw' AS source_name, COUNT(*) AS row_count, MAX(requested_at) AS latest_requested_at
FROM raw.seoul_construction_progress_raw
UNION ALL
SELECT 'seoul_construction_progress_ref' AS source_name, COUNT(*) AS row_count, MAX(requested_at) AS latest_requested_at
FROM ref.seoul_construction_progress;
