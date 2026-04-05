-- 운영 적재·coverage·stale 빠른 점검 (README 기준 보조)
-- 실행: psql -v ON_ERROR_STOP=1 -f sql/verify_operational_health.sql

\echo '=== 1) 외부 소스 적재 상태 (mart.external_source_collection_status) ==='
SELECT * FROM mart.external_source_collection_status ORDER BY source_name;

\echo '=== 2) trainset 계열 row count / split / dataset_status (\\timing on 권장) ==='
SELECT COUNT(*) AS trainset_base_rows FROM mart.seoul_district_heavyrain_trainset_base;
SELECT COUNT(*) AS trainset_pending_rows FROM mart.seoul_district_heavyrain_trainset_pending;
SELECT COUNT(*) AS trainset_labeled_rows FROM mart.seoul_district_heavyrain_trainset;
SELECT split_type, COUNT(*) AS n, COUNT(*) FILTER (WHERE is_trainable) AS trainable_n
FROM mart.seoul_district_heavyrain_trainset
GROUP BY split_type
ORDER BY CASE split_type WHEN 'train' THEN 1 WHEN 'valid' THEN 2 WHEN 'test' THEN 3 ELSE 4 END;
SELECT dataset_status, COUNT(*) AS n FROM mart.seoul_district_heavyrain_trainset_base GROUP BY dataset_status ORDER BY dataset_status;
SELECT * FROM mart.seoul_district_heavyrain_trainset LIMIT 3;

\echo '=== 3) 하천: std에 관측이 있는 구 vs 서울 25구 ==='
WITH expected AS (
    SELECT unnest(ARRAY[
        '종로구','중구','용산구','성동구','광진구','동대문구','중랑구',
        '성북구','강북구','도봉구','노원구','은평구','서대문구','마포구',
        '양천구','강서구','구로구','금천구','영등포구','동작구','관악구',
        '서초구','강남구','송파구','강동구'
    ]) AS district_name
),
std_d AS (SELECT DISTINCT district_name FROM std.seoul_river_stage_std WHERE district_name IS NOT NULL)
SELECT
    (SELECT COUNT(*) FROM std_d) AS river_std_district_count,
    (SELECT COUNT(*) FROM expected e JOIN std_d s ON s.district_name = e.district_name) AS matched_expected;

WITH expected AS (
    SELECT unnest(ARRAY[
        '종로구','중구','용산구','성동구','광진구','동대문구','중랑구',
        '성북구','강북구','도봉구','노원구','은평구','서대문구','마포구',
        '양천구','강서구','구로구','금천구','영등포구','동작구','관악구',
        '서초구','강남구','송파구','강동구'
    ]) AS district_name
),
std_d AS (SELECT DISTINCT district_name FROM std.seoul_river_stage_std WHERE district_name IS NOT NULL)
SELECT e.district_name AS no_river_std_rows
FROM expected e
WHERE NOT EXISTS (SELECT 1 FROM std_d s WHERE s.district_name = e.district_name);

\echo '=== 4) model_features 최신 ultra_now: 하천·AWS 플래그 요약 ==='
WITH latest AS (
    SELECT MAX(base_datetime) AS ts
    FROM mart.seoul_district_model_features
    WHERE product_type = 'ultra_now' AND target_datetime = base_datetime
)
SELECT
    COUNT(*) AS rows,
    COUNT(*) FILTER (WHERE river_district_has_stations) AS river_has_stations_rows,
    COUNT(*) FILTER (WHERE river_observation_present) AS river_observation_rows,
    COUNT(*) FILTER (WHERE aws_operational_stale_flag) AS aws_stale_rows,
    COUNT(*) FILTER (WHERE aws_neighbor_imputed) AS aws_imputed_rows
FROM mart.seoul_district_model_features m
JOIN latest l ON m.base_datetime = l.ts
WHERE m.product_type = 'ultra_now' AND m.target_datetime = m.base_datetime;

\echo '=== 5) 침수흔적도·위험개선지구: 원천 구 커버리지 vs mart 25구 ==='
SELECT COUNT(DISTINCT district_name) AS flood_trace_ref_districts FROM ref.seoul_flood_trace;
SELECT COUNT(DISTINCT district_name) AS risk_zone_ref_districts FROM ref.seoul_disaster_risk_zone;
SELECT COUNT(*) AS flood_features_rows, COUNT(DISTINCT district_name) AS flood_features_districts
FROM mart.seoul_district_flood_features;

WITH expected AS (
    SELECT unnest(ARRAY[
        '종로구','중구','용산구','성동구','광진구','동대문구','중랑구',
        '성북구','강북구','도봉구','노원구','은평구','서대문구','마포구',
        '양천구','강서구','구로구','금천구','영등포구','동작구','관악구',
        '서초구','강남구','송파구','강동구'
    ]) AS district_name
)
SELECT e.district_name AS missing_in_flood_trace_ref
FROM expected e
WHERE NOT EXISTS (
    SELECT 1 FROM (SELECT DISTINCT district_name FROM ref.seoul_flood_trace) f
    WHERE f.district_name = e.district_name
);

\echo '=== 6) AWS lag 분포 (최근 ultra_now 1슬라이스) ==='
WITH latest AS (
    SELECT MAX(base_datetime) AS ts
    FROM mart.seoul_district_model_features
    WHERE product_type = 'ultra_now' AND target_datetime = base_datetime
)
SELECT
    ROUND(MIN(aws_lag_minutes)::numeric, 0) AS min_lag_min,
    ROUND(MAX(aws_lag_minutes)::numeric, 0) AS max_lag_min,
    ROUND(AVG(aws_lag_minutes)::numeric, 0) AS avg_lag_min
FROM mart.seoul_district_model_features m
JOIN latest l ON m.base_datetime = l.ts
WHERE m.product_type = 'ultra_now' AND m.target_datetime = m.base_datetime AND m.aws_lag_minutes IS NOT NULL;
