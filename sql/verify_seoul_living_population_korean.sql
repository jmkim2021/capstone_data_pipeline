-- 운영 점검용: 내국인 생활인구 proxy 파이프라인 (OA-15439)
-- 실행: psql -v ON_ERROR_STOP=1 -f sql/verify_seoul_living_population_korean.sql

\echo '=== A. 최근 적재 (requested / source_date 컬럼 / base_date) ==='
SELECT requested_date::text, source_date::text, base_date::text, COUNT(*) AS n
FROM ref.seoul_living_population_korean_district_hourly
WHERE ingested_at >= NOW() - INTERVAL '7 days'
GROUP BY 1, 2, 3
ORDER BY MAX(ingested_at) DESC;

\echo '=== A. 최근 7일 base_date별 행 수 ==='
SELECT base_date, COUNT(*) AS rows, COUNT(DISTINCT district_code) AS districts
FROM ref.seoul_living_population_korean_district_hourly
WHERE ingested_at >= NOW() - INTERVAL '7 days'
GROUP BY base_date
ORDER BY base_date DESC;

\echo '=== B. latest 행 수·중복 ==='
SELECT COUNT(*) AS latest_rows FROM mart.seoul_living_population_korean_district_latest;
SELECT district_code, COUNT(*) AS c
FROM mart.seoul_living_population_korean_district_latest
GROUP BY district_code
HAVING COUNT(*) > 1;

\echo '=== B. latest base_date / base_hour 분포 ==='
SELECT base_date, base_hour, COUNT(*) AS n
FROM mart.seoul_living_population_korean_district_latest
GROUP BY 1, 2
ORDER BY 1 DESC, 2 DESC;

\echo '=== C. realtime: 건수·floating_pop null 비율·lag 통계 ==='
SELECT COUNT(*) AS n,
       COUNT(floating_pop_korean) AS fp_non_null,
       ROUND(100.0 * COUNT(floating_pop_korean) / NULLIF(COUNT(*), 0), 2) AS fp_fill_pct
FROM mart.seoul_district_realtime_features_latest;

SELECT
    ROUND(MIN(floating_pop_korean_lag_hours)::numeric, 2) AS lag_min_h,
    ROUND(MAX(floating_pop_korean_lag_hours)::numeric, 2) AS lag_max_h,
    ROUND(AVG(floating_pop_korean_lag_hours)::numeric, 2) AS lag_avg_h
FROM mart.seoul_district_realtime_features_latest
WHERE floating_pop_korean_lag_hours IS NOT NULL;

\echo '=== D. 샘플 10구 ==='
SELECT district_name,
       base_datetime,
       floating_pop_korean_base_date,
       floating_pop_korean_base_hour,
       floating_pop_korean_observed_at,
       floating_pop_korean,
       floating_pop_korean_lag_hours
FROM mart.seoul_district_realtime_features_latest
ORDER BY district_name
LIMIT 10;

\echo '=== E. lag 구간별 건수 (운영 stale 해석용; 조인 성공 ≠ 실시간성 보장) ==='
SELECT
    COUNT(*) FILTER (WHERE floating_pop_korean_lag_hours <= 24) AS lag_le_24h,
    COUNT(*) FILTER (WHERE floating_pop_korean_lag_hours > 24 AND floating_pop_korean_lag_hours <= 72) AS lag_24_72h,
    COUNT(*) FILTER (WHERE floating_pop_korean_lag_hours > 72) AS lag_gt_72h
FROM mart.seoul_district_realtime_features_latest
WHERE floating_pop_korean_lag_hours IS NOT NULL;

\echo '=== E. 최근 7일 ref 적재 중 max(source_date) ==='
SELECT MAX(source_date) AS max_source_date_in_recent_ingest
FROM ref.seoul_living_population_korean_district_hourly
WHERE ingested_at >= NOW() - INTERVAL '7 days';
