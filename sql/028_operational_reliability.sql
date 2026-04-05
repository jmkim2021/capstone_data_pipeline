-- ---------------------------------------------------------------------------
-- 운영 신뢰성·검증 가능성 보강 (인덱스, external_source_collection_status 통합)
-- 적용: psql -v ON_ERROR_STOP=1 -f sql/028_operational_reliability.sql
-- 선행: 010(테이블), 015(HSR area 테이블), 027(model_features 보조 플래그), 016(trainset 성능)
-- ---------------------------------------------------------------------------
-- - mart.seoul_district_model_features 보조 컬럼: sql/027_seoul_district_model_features_v2.sql
-- - trainset 성능(MATERIALIZED decision_base 등): sql/016_seoul_district_heavyrain_datasets.sql
-- ---------------------------------------------------------------------------

-- 1) mart 최신 슬라이스 조회용 인덱스 (lateral ORDER BY observed_at DESC LIMIT 1)
CREATE INDEX IF NOT EXISTS idx_mart_seoul_rainfall_district_latest_district_obs
    ON mart.seoul_rainfall_district_latest (district_name, observed_at DESC);

CREATE INDEX IF NOT EXISTS idx_mart_seoul_river_stage_district_latest_district_obs
    ON mart.seoul_river_stage_district_latest (district_name, observed_minute DESC);

-- 2) 외부 소스 적재 상태: HSR 구단위(area) + 건설공사 + 생활인구 등 한 뷰에 통합
CREATE OR REPLACE VIEW mart.external_source_collection_status AS
SELECT 'seoul_rainfall_raw' AS source_name, COUNT(*)::bigint AS row_count, MAX(requested_at) AS latest_requested_at
FROM raw.seoul_rainfall_raw
UNION ALL
SELECT 'seoul_rainfall_std', COUNT(*)::bigint, MAX(requested_at)
FROM std.seoul_rainfall_std
UNION ALL
SELECT 'seoul_river_stage_raw', COUNT(*)::bigint, MAX(requested_at)
FROM raw.seoul_river_stage_raw
UNION ALL
SELECT 'seoul_river_stage_std', COUNT(*)::bigint, MAX(requested_at)
FROM std.seoul_river_stage_std
UNION ALL
SELECT 'kma_hsr_request_raw', COUNT(*)::bigint, MAX(requested_at)
FROM raw.kma_hsr_request_raw
UNION ALL
SELECT 'kma_hsr_file_inventory_std', COUNT(*)::bigint, MAX(requested_at)
FROM std.kma_hsr_file_inventory_std
UNION ALL
SELECT 'kma_hsr_area_raw', COUNT(*)::bigint, MAX(requested_at)
FROM raw.kma_hsr_area_raw
UNION ALL
SELECT 'kma_hsr_area_district_std', COUNT(*)::bigint, MAX(requested_at)
FROM std.kma_hsr_area_district_std
UNION ALL
SELECT 'seoul_construction_progress_raw', COUNT(*)::bigint, MAX(requested_at)
FROM raw.seoul_construction_progress_raw
UNION ALL
SELECT 'seoul_construction_progress_ref', COUNT(*)::bigint, MAX(requested_at)
FROM ref.seoul_construction_progress
UNION ALL
SELECT 'seoul_living_population_korean_district_hourly', COUNT(*)::bigint, MAX(ingested_at)
FROM ref.seoul_living_population_korean_district_hourly;
