-- ===========================================================================
-- 최종 검수: 취약계층 밀집도 적재 + mart.seoul_district_model_features 조인
-- 실행: psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -f sql/verify_seoul_vulnerable_population_final_audit.sql
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- A. district_name 정합성 (ref vs model_features vs meta 격자표)
-- ---------------------------------------------------------------------------
\echo '=== A1. distinct count ==='
WITH ref_d AS (SELECT DISTINCT district_name FROM ref.seoul_vulnerable_population_district_snapshot),
mf_d AS (SELECT DISTINCT district_name FROM mart.seoul_district_model_features),
meta_d AS (SELECT DISTINCT district_name FROM meta.seoul_district_grid_map)
SELECT
    (SELECT COUNT(*) FROM ref_d) AS ref_distinct,
    (SELECT COUNT(*) FROM mf_d) AS mf_distinct,
    (SELECT COUNT(*) FROM meta_d) AS meta_distinct;

\echo '=== A2. ref_only / mf_only (0행이어야 함) ==='
WITH ref_d AS (SELECT DISTINCT district_name FROM ref.seoul_vulnerable_population_district_snapshot),
mf_d AS (SELECT DISTINCT district_name FROM mart.seoul_district_model_features)
SELECT kind, district_name FROM (
    SELECT 'ref_only'::text AS kind, r.district_name
    FROM ref_d r
    WHERE NOT EXISTS (SELECT 1 FROM mf_d m WHERE m.district_name = r.district_name)
    UNION ALL
    SELECT 'mf_only', m.district_name
    FROM mf_d m
    WHERE NOT EXISTS (SELECT 1 FROM ref_d r WHERE r.district_name = m.district_name)
) t
ORDER BY kind, district_name;

\echo '=== A3. meta_grid vs ref (0행이어야 함) ==='
WITH ref_d AS (SELECT DISTINCT district_name FROM ref.seoul_vulnerable_population_district_snapshot),
meta_d AS (SELECT DISTINCT district_name FROM meta.seoul_district_grid_map)
SELECT kind, district_name FROM (
    SELECT 'meta_only'::text AS kind, x.district_name
    FROM meta_d x
    WHERE NOT EXISTS (SELECT 1 FROM ref_d r WHERE r.district_name = x.district_name)
    UNION ALL
    SELECT 'ref_only', r.district_name
    FROM ref_d r
    WHERE NOT EXISTS (SELECT 1 FROM meta_d x WHERE x.district_name = r.district_name)
) t
ORDER BY kind, district_name;

\echo '=== A4. 공백/trim 이상 (0행) ==='
SELECT district_name
FROM ref.seoul_vulnerable_population_district_snapshot
WHERE district_name <> btrim(district_name)
   OR district_name LIKE '% %';

-- ---------------------------------------------------------------------------
-- B. join 안정성 (model_features × vulnerable latest)
-- ---------------------------------------------------------------------------
\echo '=== B1. row explosion (cnt = grain 이어야 함) ==='
SELECT
    COUNT(*) AS mf_row_count,
    COUNT(DISTINCT (product_type, district_name, base_datetime, target_datetime, lead_minutes)) AS mf_grain
FROM mart.seoul_district_model_features;

\echo '=== B2. 취약계층 컬럼 조인 누락 (NULL 증가) — 전부 채워지면 0 ==='
SELECT COUNT(*) AS rows_with_null_elderly_total
FROM mart.seoul_district_model_features
WHERE elderly_population_total IS NULL;

\echo '=== B3. latest vs model_features (구별 취약 feature 값 일치) ==='
SELECT COUNT(*) AS mismatched_districts
FROM mart.seoul_vulnerable_population_district_latest v
WHERE EXISTS (
    SELECT 1
    FROM mart.seoul_district_model_features m
    WHERE m.district_name = v.district_name
      AND m.elderly_population_total IS NOT NULL
      AND m.elderly_population_total IS DISTINCT FROM v.elderly_population_total
    LIMIT 1
)
OR NOT EXISTS (
    SELECT 1 FROM mart.seoul_district_model_features m
    WHERE m.district_name = v.district_name AND m.elderly_population_total IS NOT NULL
);

-- ---------------------------------------------------------------------------
-- C. ratio 정의 검증 (ref 테이블)
-- ---------------------------------------------------------------------------
\echo '=== C1. ratio min/max ==='
SELECT
    MIN(elderly_population_ratio) AS el_min,
    MAX(elderly_population_ratio) AS el_max,
    MIN(disabled_population_ratio) AS di_min,
    MAX(disabled_population_ratio) AS di_max,
    MIN(basic_livelihood_recipient_ratio) AS bl_min,
    MAX(basic_livelihood_recipient_ratio) AS bl_max,
    MIN(aged_basement_household_ratio) AS ab_min,
    MAX(aged_basement_household_ratio) AS ab_max
FROM ref.seoul_vulnerable_population_district_snapshot;

\echo '=== C2. ratio 범위 이탈 건수 (모두 0) ==='
SELECT
    COUNT(*) FILTER (WHERE elderly_population_ratio < 0 OR elderly_population_ratio > 1) AS el_bad,
    COUNT(*) FILTER (WHERE disabled_population_ratio < 0 OR disabled_population_ratio > 1) AS di_bad,
    COUNT(*) FILTER (WHERE basic_livelihood_recipient_ratio < 0 OR basic_livelihood_recipient_ratio > 1) AS bl_bad,
    COUNT(*) FILTER (WHERE aged_basement_household_ratio < 0 OR aged_basement_household_ratio > 1) AS ab_bad
FROM ref.seoul_vulnerable_population_district_snapshot;

\echo '=== C3. 재계산 일치 (고령자 ratio) — 오차 허용 1e-6 ==='
SELECT COUNT(*) AS mismatch_elderly_ratio
FROM ref.seoul_vulnerable_population_district_snapshot
WHERE total_population > 0
  AND ABS(elderly_population_ratio - (elderly_population_total::double precision / total_population)) > 1e-6;

-- ---------------------------------------------------------------------------
-- D. 샘플 10행 (현실성 육안 점검)
-- ---------------------------------------------------------------------------
\echo '=== D. 샘플 10행 ==='
SELECT
    district_name,
    elderly_population_total,
    ROUND(elderly_population_ratio::numeric, 4) AS elderly_population_ratio,
    disabled_population_total,
    ROUND(disabled_population_ratio::numeric, 4) AS disabled_population_ratio,
    basic_livelihood_recipient_total,
    ROUND(basic_livelihood_recipient_ratio::numeric, 4) AS basic_livelihood_recipient_ratio,
    basement_household_count,
    aged_basement_household_count,
    ROUND(aged_basement_household_ratio::numeric, 4) AS aged_basement_household_ratio
FROM ref.seoul_vulnerable_population_district_snapshot
ORDER BY district_name
LIMIT 10;

-- ---------------------------------------------------------------------------
-- E. 영향 범위 (mart row / 구 수)
-- ---------------------------------------------------------------------------
\echo '=== E. model_features 구별 행 수 (대표 시각) ==='
WITH one_ts AS (
    SELECT MAX(base_datetime) AS ts FROM mart.seoul_district_model_features
)
SELECT COUNT(*) AS rows_at_max_ts
FROM mart.seoul_district_model_features m
WHERE m.base_datetime = (SELECT ts FROM one_ts);

\echo '=== E. 의존 뷰 존재 여부 ==='
SELECT c.relname
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'mart'
  AND c.relname IN (
      'seoul_district_model_features',
      'seoul_district_realtime_features_latest',
      'seoul_district_heavyrain_trainset_base'
  )
ORDER BY c.relname;
