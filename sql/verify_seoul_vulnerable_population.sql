-- ===========================================================================
-- 검증 쿼리: ref.seoul_vulnerable_population_district_snapshot
--           + mart.seoul_vulnerable_population_district_latest
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. 기본 row count / district count
-- ---------------------------------------------------------------------------
SELECT
    COUNT(*)                AS row_count,            -- 기대값: 25
    COUNT(DISTINCT district_name) AS district_count  -- 기대값: 25
FROM ref.seoul_vulnerable_population_district_snapshot;

-- ---------------------------------------------------------------------------
-- 2. 중복 district_name 확인
-- ---------------------------------------------------------------------------
SELECT district_name, COUNT(*) AS cnt
FROM ref.seoul_vulnerable_population_district_snapshot
GROUP BY district_name
HAVING COUNT(*) > 1;
-- 기대값: 0 행

-- ---------------------------------------------------------------------------
-- 3. 25개 자치구 누락 확인
-- ---------------------------------------------------------------------------
WITH expected AS (
    SELECT unnest(ARRAY[
        '종로구','중구','용산구','성동구','광진구','동대문구','중랑구',
        '성북구','강북구','도봉구','노원구','은평구','서대문구','마포구',
        '양천구','강서구','구로구','금천구','영등포구','동작구','관악구',
        '서초구','강남구','송파구','강동구'
    ]) AS district_name
)
SELECT e.district_name AS missing_district
FROM expected e
LEFT JOIN ref.seoul_vulnerable_population_district_snapshot s
    ON s.district_name = e.district_name
WHERE s.district_name IS NULL;
-- 기대값: 0 행

-- ---------------------------------------------------------------------------
-- 4. NULL 현황
-- ---------------------------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE total_population IS NULL)                AS null_total_population,
    COUNT(*) FILTER (WHERE elderly_population_total IS NULL)        AS null_elderly_total,
    COUNT(*) FILTER (WHERE elderly_population_ratio IS NULL)        AS null_elderly_ratio,
    COUNT(*) FILTER (WHERE elderly_population_korean_total IS NULL) AS null_elderly_korean,
    COUNT(*) FILTER (WHERE elderly_population_foreign_total IS NULL)AS null_elderly_foreign,
    COUNT(*) FILTER (WHERE disabled_population_total IS NULL)       AS null_disabled_total,
    COUNT(*) FILTER (WHERE disabled_population_ratio IS NULL)       AS null_disabled_ratio,
    COUNT(*) FILTER (WHERE disabled_population_male IS NULL)        AS null_disabled_male,
    COUNT(*) FILTER (WHERE disabled_population_female IS NULL)      AS null_disabled_female,
    COUNT(*) FILTER (WHERE basic_livelihood_recipient_total IS NULL)AS null_basic_total,
    COUNT(*) FILTER (WHERE basic_livelihood_recipient_ratio IS NULL)AS null_basic_ratio,
    COUNT(*) FILTER (WHERE basic_livelihood_household_count IS NULL)AS null_basic_household,
    COUNT(*) FILTER (WHERE basement_household_count IS NULL)        AS null_basement,
    COUNT(*) FILTER (WHERE aged_basement_household_count IS NULL)   AS null_aged_basement,
    COUNT(*) FILTER (WHERE aged_basement_household_ratio IS NULL)   AS null_aged_basement_ratio
FROM ref.seoul_vulnerable_population_district_snapshot;
-- 기대값: 핵심 컬럼 모두 0

-- ---------------------------------------------------------------------------
-- 5. 비율 범위 확인 (0.0~1.0)
-- ---------------------------------------------------------------------------
SELECT
    district_name,
    elderly_population_ratio,
    disabled_population_ratio,
    basic_livelihood_recipient_ratio,
    aged_basement_household_ratio
FROM ref.seoul_vulnerable_population_district_snapshot
WHERE
    elderly_population_ratio        NOT BETWEEN 0.0 AND 1.0
    OR disabled_population_ratio    NOT BETWEEN 0.0 AND 1.0
    OR basic_livelihood_recipient_ratio NOT BETWEEN 0.0 AND 1.0
    OR aged_basement_household_ratio NOT BETWEEN 0.0 AND 1.0;
-- 기대값: 0 행

-- ---------------------------------------------------------------------------
-- 6. source year / label 확인
-- ---------------------------------------------------------------------------
SELECT
    MIN(elderly_source_year)            AS elderly_year_min,
    MAX(elderly_source_year)            AS elderly_year_max,
    MIN(DISTINCT elderly_source_label)  AS elderly_label,
    MIN(disabled_source_year)           AS disabled_year_min,
    MAX(disabled_source_year)           AS disabled_year_max,
    MIN(basic_livelihood_source_year)   AS basic_year_min,
    MAX(basic_livelihood_source_year)   AS basic_year_max,
    COUNT(DISTINCT basement_source_note) AS basement_note_variants
FROM ref.seoul_vulnerable_population_district_snapshot;
-- 기대값: elderly=2025, disabled=2024, basic=2024

-- ---------------------------------------------------------------------------
-- 7. 전체 인구 합산 검증 (서울 총 인구 ~ 9.5백만)
-- ---------------------------------------------------------------------------
SELECT
    SUM(total_population)             AS seoul_total_pop,
    SUM(elderly_population_total)     AS seoul_elderly_total,
    SUM(disabled_population_total)    AS seoul_disabled_total,
    SUM(basic_livelihood_recipient_total) AS seoul_basic_total,
    SUM(basement_household_count)     AS seoul_basement_total,
    ROUND(AVG(elderly_population_ratio)::numeric, 4) AS avg_elderly_ratio,
    ROUND(AVG(disabled_population_ratio)::numeric, 4) AS avg_disabled_ratio,
    ROUND(AVG(basic_livelihood_recipient_ratio)::numeric, 4) AS avg_basic_ratio,
    ROUND(AVG(aged_basement_household_ratio)::numeric, 4) AS avg_aged_basement_ratio
FROM ref.seoul_vulnerable_population_district_snapshot;

-- ---------------------------------------------------------------------------
-- 8. 샘플 10행 출력
-- ---------------------------------------------------------------------------
SELECT
    district_name,
    total_population,
    elderly_population_total,
    ROUND(elderly_population_ratio::numeric, 4)         AS elderly_ratio,
    disabled_population_total,
    ROUND(disabled_population_ratio::numeric, 4)        AS disabled_ratio,
    basic_livelihood_recipient_total,
    ROUND(basic_livelihood_recipient_ratio::numeric, 4) AS basic_ratio,
    basement_household_count,
    aged_basement_household_count,
    ROUND(aged_basement_household_ratio::numeric, 4)    AS aged_basement_ratio,
    elderly_source_label,
    disabled_source_year,
    basic_livelihood_source_year,
    updated_at
FROM ref.seoul_vulnerable_population_district_snapshot
ORDER BY district_name
LIMIT 10;

-- ---------------------------------------------------------------------------
-- 9. mart latest view row count 확인
-- ---------------------------------------------------------------------------
SELECT COUNT(*) AS mart_latest_row_count   -- 기대값: 25
FROM mart.seoul_vulnerable_population_district_latest;

-- ---------------------------------------------------------------------------
-- 10. mart latest view - 25개 자치구 목록
-- ---------------------------------------------------------------------------
SELECT district_name, elderly_population_ratio, disabled_population_ratio,
       basic_livelihood_recipient_ratio, aged_basement_household_ratio
FROM mart.seoul_vulnerable_population_district_latest
ORDER BY district_name;

-- ---------------------------------------------------------------------------
-- 11. (선택) mart.seoul_district_model_features에서 취약계층 컬럼 join 확인
--     ref.seoul_vulnerable_population_district_snapshot 적재 + 027 SQL 실행 후 유효
-- ---------------------------------------------------------------------------
/*
SELECT
    district_name,
    elderly_population_total,
    elderly_population_ratio,
    disabled_population_total,
    disabled_population_ratio,
    basic_livelihood_recipient_total,
    basement_household_count,
    aged_basement_household_ratio
FROM mart.seoul_district_model_features
WHERE base_datetime = (SELECT MAX(base_datetime) FROM mart.seoul_district_model_features)
ORDER BY district_name
LIMIT 5;
*/
