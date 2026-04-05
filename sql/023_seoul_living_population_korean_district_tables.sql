BEGIN;

CREATE SCHEMA IF NOT EXISTS ref;
CREATE SCHEMA IF NOT EXISTS mart;

-- 5자리 자치구 코드(예: 11110=종로구) -> 표준 자치구명 매핑
-- (HSR 수집기에서 쓰는 10자리 코드의 앞 5자리를 사용)
CREATE TABLE IF NOT EXISTS ref.seoul_district_code_map (
    district_code TEXT PRIMARY KEY,
    district_name TEXT NOT NULL
);

-- Upsert style: 스키마 재실행 시 값 유지
INSERT INTO ref.seoul_district_code_map (district_code, district_name) VALUES
    ('11110', '종로구'),
    ('11140', '중구'),
    ('11170', '용산구'),
    ('11200', '성동구'),
    ('11215', '광진구'),
    ('11230', '동대문구'),
    ('11260', '중랑구'),
    ('11290', '성북구'),
    ('11305', '강북구'),
    ('11320', '도봉구'),
    ('11350', '노원구'),
    ('11380', '은평구'),
    ('11410', '서대문구'),
    ('11440', '마포구'),
    ('11470', '양천구'),
    ('11500', '강서구'),
    ('11530', '구로구'),
    ('11545', '금천구'),
    ('11560', '영등포구'),
    ('11590', '동작구'),
    ('11620', '관악구'),
    ('11650', '서초구'),
    ('11680', '강남구'),
    ('11710', '송파구'),
    ('11740', '강동구')
ON CONFLICT (district_code) DO UPDATE SET
    district_name = EXCLUDED.district_name;

-- OA-15439 (자치구 단위 서울 생활인구(내국인)) 기반:
-- "내국인 생활인구 1차 proxy"로만 사용 (총 생활인구(total) 아님)
CREATE TABLE IF NOT EXISTS ref.seoul_living_population_korean_district_hourly (
    base_date DATE NOT NULL,
    base_hour INTEGER NOT NULL,
    district_code TEXT NOT NULL,
    district_name TEXT NOT NULL,
    korean_population DOUBLE PRECISION NOT NULL,
    -- 이번 작업에서는 데이터 자체의 기준일/시각이 base_date/base_hour
    source_date DATE NOT NULL,
    source_name TEXT NOT NULL,
    requested_date DATE,
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    row_json JSONB,
    PRIMARY KEY (base_date, base_hour, district_code)
);

CREATE INDEX IF NOT EXISTS idx_ref_living_pop_korean_hourly_district
    ON ref.seoul_living_population_korean_district_hourly (district_name);
CREATE INDEX IF NOT EXISTS idx_ref_living_pop_korean_hourly_base
    ON ref.seoul_living_population_korean_district_hourly (base_date DESC, base_hour DESC);

-- 자치구별 "가장 최근 공개/적재된" 내국인 생활인구 1행(대시보드·스냅샷용).
-- mart.seoul_district_realtime_features_latest의 floating_pop_korean은
-- base_datetime 이하 as-of 조인(016)을 쓰므로 이 뷰와 값이 다를 수 있음.
CREATE OR REPLACE VIEW mart.seoul_living_population_korean_district_latest AS
SELECT DISTINCT ON (district_code)
    updated_at AS as_of_time,
    base_date,
    base_hour,
    district_code,
    district_name,
    korean_population
FROM ref.seoul_living_population_korean_district_hourly
ORDER BY district_code, base_date DESC, base_hour DESC, updated_at DESC;

COMMIT;

