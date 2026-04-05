CREATE TABLE IF NOT EXISTS raw.seoul_disaster_risk_zone_raw (
    id BIGSERIAL PRIMARY KEY,
    source_file_name TEXT NOT NULL,
    source_encoding TEXT NOT NULL,
    source_row_number INTEGER NOT NULL,
    source_serial_no INTEGER,
    row_json JSONB NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_raw_seoul_disaster_risk_zone_raw_row
    ON raw.seoul_disaster_risk_zone_raw (source_file_name, source_row_number);

CREATE TABLE IF NOT EXISTS ref.seoul_disaster_risk_zone (
    id BIGSERIAL PRIMARY KEY,
    source_file_name TEXT NOT NULL,
    source_encoding TEXT NOT NULL,
    source_row_number INTEGER NOT NULL,
    serial_no INTEGER,
    zone_name TEXT NOT NULL,
    risk_type TEXT,
    location_text TEXT,
    district_name TEXT,
    facility_name TEXT,
    facility_type TEXT,
    designated_date DATE,
    designation_reason TEXT,
    risk_factor TEXT,
    progress_status TEXT,
    managing_agency TEXT,
    managing_contact TEXT,
    has_geometry BOOLEAN NOT NULL DEFAULT FALSE,
    geom geometry(Geometry, 4326),
    source_row_hash TEXT NOT NULL,
    row_json JSONB NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_ref_seoul_disaster_risk_zone_row
    ON ref.seoul_disaster_risk_zone (source_file_name, source_row_number);

CREATE INDEX IF NOT EXISTS idx_ref_seoul_disaster_risk_zone_district
    ON ref.seoul_disaster_risk_zone (district_name);

CREATE INDEX IF NOT EXISTS idx_ref_seoul_disaster_risk_zone_status
    ON ref.seoul_disaster_risk_zone (progress_status);

CREATE INDEX IF NOT EXISTS idx_ref_seoul_disaster_risk_zone_geom
    ON ref.seoul_disaster_risk_zone
    USING GIST (geom);

CREATE OR REPLACE VIEW ref.seoul_disaster_risk_zone_summary AS
SELECT
    COALESCE(district_name, '미분류') AS district_name,
    COUNT(*) AS zone_count,
    COUNT(*) FILTER (WHERE progress_status = '추진중') AS in_progress_count,
    COUNT(*) FILTER (WHERE progress_status = '고시실효') AS expired_count
FROM ref.seoul_disaster_risk_zone
GROUP BY COALESCE(district_name, '미분류')
ORDER BY district_name;
