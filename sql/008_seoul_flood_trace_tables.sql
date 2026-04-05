CREATE TABLE IF NOT EXISTS raw.seoul_flood_trace_raw (
    id BIGSERIAL PRIMARY KEY,
    source_year INTEGER NOT NULL,
    source_file_name TEXT NOT NULL,
    layer_name TEXT NOT NULL,
    feature_index INTEGER NOT NULL,
    original_crs TEXT,
    source_properties JSONB NOT NULL,
    geom geometry(MultiPolygon, 4326) NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_raw_seoul_flood_trace_raw_feature
    ON raw.seoul_flood_trace_raw (source_file_name, layer_name, feature_index);

CREATE INDEX IF NOT EXISTS idx_raw_seoul_flood_trace_raw_year
    ON raw.seoul_flood_trace_raw (source_year);

CREATE INDEX IF NOT EXISTS idx_raw_seoul_flood_trace_raw_geom
    ON raw.seoul_flood_trace_raw
    USING GIST (geom);

CREATE TABLE IF NOT EXISTS ref.seoul_flood_trace (
    id BIGSERIAL PRIMARY KEY,
    source_year INTEGER NOT NULL,
    source_file_name TEXT NOT NULL,
    layer_name TEXT NOT NULL,
    feature_index INTEGER NOT NULL,
    pnu_text TEXT,
    adm_cd TEXT,
    district_name TEXT,
    flood_zone_name TEXT,
    damage_address TEXT,
    property_type TEXT,
    support_type TEXT,
    disaster_name TEXT,
    damage_reason_detail TEXT,
    flood_start_date TEXT,
    flood_end_date TEXT,
    flood_start_time TEXT,
    flood_end_time TEXT,
    inundation_depth_m DOUBLE PRECISION,
    flooded_area_sqm DOUBLE PRECISION,
    avg_elevation_m DOUBLE PRECISION,
    inventory_year TEXT,
    original_crs TEXT,
    source_properties JSONB NOT NULL,
    geom geometry(MultiPolygon, 4326) NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_ref_seoul_flood_trace_feature
    ON ref.seoul_flood_trace (source_file_name, layer_name, feature_index);

CREATE INDEX IF NOT EXISTS idx_ref_seoul_flood_trace_year
    ON ref.seoul_flood_trace (source_year);

CREATE INDEX IF NOT EXISTS idx_ref_seoul_flood_trace_district
    ON ref.seoul_flood_trace (district_name);

CREATE INDEX IF NOT EXISTS idx_ref_seoul_flood_trace_adm_cd
    ON ref.seoul_flood_trace (adm_cd);

CREATE INDEX IF NOT EXISTS idx_ref_seoul_flood_trace_geom
    ON ref.seoul_flood_trace
    USING GIST (geom);

CREATE OR REPLACE VIEW ref.seoul_flood_trace_year_summary AS
SELECT
    source_year,
    COUNT(*) AS feature_count,
    COUNT(DISTINCT district_name) AS district_count,
    ROUND(SUM(flooded_area_sqm)::numeric, 2) AS flooded_area_sqm_sum,
    ROUND(AVG(inundation_depth_m)::numeric, 4) AS avg_inundation_depth_m
FROM ref.seoul_flood_trace
GROUP BY source_year
ORDER BY source_year;
