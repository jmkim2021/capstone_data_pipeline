CREATE TABLE IF NOT EXISTS raw.seoul_construction_progress_raw (
    id BIGSERIAL PRIMARY KEY,
    requested_at TIMESTAMPTZ NOT NULL,
    source_service_name TEXT NOT NULL,
    source_row_number INTEGER NOT NULL,
    biz_cd TEXT,
    raw_gu_cd TEXT,
    raw_gu_name TEXT,
    normalized_district_name TEXT,
    is_loaded BOOLEAN NOT NULL,
    exclusion_reason TEXT,
    response_json JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_raw_seoul_construction_progress_requested
    ON raw.seoul_construction_progress_raw (requested_at DESC, biz_cd);

CREATE INDEX IF NOT EXISTS idx_raw_seoul_construction_progress_loaded
    ON raw.seoul_construction_progress_raw (is_loaded, exclusion_reason);

CREATE TABLE IF NOT EXISTS ref.seoul_construction_progress (
    biz_cd TEXT PRIMARY KEY,
    district_name TEXT NOT NULL,
    contractor_name TEXT,
    ordering_agency_name TEXT,
    project_name TEXT NOT NULL,
    completion_status TEXT,
    raw_gu_cd TEXT,
    raw_gu_name TEXT,
    source_row_hash TEXT NOT NULL,
    row_json JSONB NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ref_seoul_construction_progress_district
    ON ref.seoul_construction_progress (district_name);

CREATE INDEX IF NOT EXISTS idx_ref_seoul_construction_progress_completion
    ON ref.seoul_construction_progress (completion_status);

CREATE OR REPLACE VIEW ref.seoul_construction_progress_summary AS
SELECT
    district_name,
    completion_status,
    COUNT(*) AS project_count,
    MAX(requested_at) AS latest_requested_at
FROM ref.seoul_construction_progress
GROUP BY district_name, completion_status
ORDER BY district_name, completion_status;
