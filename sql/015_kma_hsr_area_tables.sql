CREATE TABLE IF NOT EXISTS raw.kma_hsr_area_raw (
    id BIGSERIAL PRIMARY KEY,
    requested_at TIMESTAMPTZ NOT NULL,
    base_datetime TIMESTAMPTZ NOT NULL,
    district_code TEXT NOT NULL,
    district_name TEXT NOT NULL,
    comp_type TEXT NOT NULL,
    data_type_cd TEXT NOT NULL,
    http_status INTEGER,
    result_code TEXT,
    is_success BOOLEAN NOT NULL,
    error_message TEXT,
    response_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_raw_kma_hsr_area_raw_base
    ON raw.kma_hsr_area_raw (base_datetime DESC, district_code);

CREATE TABLE IF NOT EXISTS std.kma_hsr_area_district_std (
    base_datetime TIMESTAMPTZ NOT NULL,
    district_code TEXT NOT NULL,
    district_name TEXT NOT NULL,
    comp_type TEXT NOT NULL,
    data_type_cd TEXT NOT NULL,
    lon DOUBLE PRECISION,
    lat DOUBLE PRECISION,
    unit TEXT,
    value_numeric DOUBLE PRECISION,
    raw_value_text TEXT,
    is_no_echo BOOLEAN,
    requested_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (base_datetime, district_code, comp_type, data_type_cd)
);

CREATE INDEX IF NOT EXISTS idx_std_kma_hsr_area_district_std_latest
    ON std.kma_hsr_area_district_std (district_name, base_datetime DESC);

CREATE OR REPLACE VIEW mart.kma_hsr_area_district_latest AS
SELECT DISTINCT ON (district_code, comp_type, data_type_cd)
    base_datetime,
    district_code,
    district_name,
    comp_type,
    data_type_cd,
    lon,
    lat,
    unit,
    value_numeric,
    raw_value_text,
    is_no_echo,
    requested_at
FROM std.kma_hsr_area_district_std
ORDER BY district_code, comp_type, data_type_cd, base_datetime DESC;

-- mart.external_source_collection_status 정의는 sql/028_operational_reliability.sql 에 통합한다.
-- (구버전: 이 파일에서 뷰를 덮어쓰면 OA-2540 등 다른 외부 소스 행이 사라질 수 있음)
