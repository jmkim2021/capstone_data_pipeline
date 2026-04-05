BEGIN;

CREATE SCHEMA IF NOT EXISTS ref;
CREATE SCHEMA IF NOT EXISTS mart;

CREATE TABLE IF NOT EXISTS ref.seoul_district_worker_stats (
    base_year INT NOT NULL,
    district_name TEXT NOT NULL,
    total_worker_count INT NOT NULL,
    source_file_name TEXT NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (base_year, district_name)
);

CREATE INDEX IF NOT EXISTS idx_ref_seoul_district_worker_stats_district
    ON ref.seoul_district_worker_stats (district_name);

CREATE OR REPLACE VIEW mart.seoul_district_worker_features AS
SELECT
    base_year,
    district_name,
    total_worker_count
FROM ref.seoul_district_worker_stats;

COMMIT;
