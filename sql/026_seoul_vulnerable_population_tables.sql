BEGIN;

CREATE SCHEMA IF NOT EXISTS ref;
CREATE SCHEMA IF NOT EXISTS mart;

-- ---------------------------------------------------------------------------
-- ref.seoul_vulnerable_population_district_snapshot
-- ---------------------------------------------------------------------------
-- 서울 자치구 단위 취약계층 밀집도 관련 참조 스냅샷.
-- 데이터 성격: 준정적(slow-changing) — 연·분기 갱신 대상.
-- 소스 파일마다 기준 시점이 다르므로 공통 base_date 대신 컴포넌트별 source 시점을 분리 저장.
--
-- 비율(ratio) 저장 단위: 소수(0.0 ~ 1.0)
--   예외: aged_basement_household_ratio — 원본 파일이 %(0~100)이므로 /100 변환 후 저장.
--
-- ratio 분모:
--   - elderly_population_ratio    : total_population (고령자현황, 동일 소스 2025 Q4)
--   - disabled_population_ratio   : total_population (고령자현황 2025 Q4 재사용 ← 장애인현황 소스년도=2024 상이)
--   - basic_livelihood_recipient_ratio : total_population (고령자현황 2025 Q4 재사용 ← 기초생보 소스년도=2024 상이)
--   분모 소스 시점 차이는 elderly_source_year / disabled_source_year / basic_livelihood_source_year로 구분 가능.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ref.seoul_vulnerable_population_district_snapshot (
    district_name                       TEXT        NOT NULL,

    -- 전체 인구 (고령자현황 소스, ratio 분모로 사용)
    total_population                    INTEGER,

    -- 고령자 features
    elderly_population_total            INTEGER,
    elderly_population_ratio            DOUBLE PRECISION,   -- 0.0~1.0
    elderly_population_korean_total     INTEGER,
    elderly_population_foreign_total    INTEGER,

    -- 장애인 features
    disabled_population_total           INTEGER,
    disabled_population_ratio           DOUBLE PRECISION,   -- 0.0~1.0 (분모=고령자현황 total_population, 소스년도 상이)
    disabled_population_male            INTEGER,
    disabled_population_female          INTEGER,

    -- 국민기초생활보장 수급자 features
    basic_livelihood_recipient_total    INTEGER,
    basic_livelihood_recipient_ratio    DOUBLE PRECISION,   -- 0.0~1.0 (분모=고령자현황 total_population, 소스년도 상이)
    basic_livelihood_household_count    INTEGER,

    -- 지하·반지하주택 features
    basement_household_count            INTEGER,
    aged_basement_household_count       INTEGER,
    aged_basement_household_ratio       DOUBLE PRECISION,   -- 0.0~1.0 (원본 % /100 변환)

    -- 컴포넌트별 소스 시점 (소스마다 기준일이 달라 분리 저장)
    elderly_source_label                TEXT,   -- 예: '2025 4/4' (원본 표기 그대로)
    elderly_source_year                 INTEGER, -- 예: 2025
    disabled_source_year                INTEGER, -- 예: 2024
    basic_livelihood_source_year        INTEGER, -- 예: 2024
    basement_source_note                TEXT,    -- 예: '출처일 미표기; 수집일 2026-04-03'

    -- 감사 컬럼
    source_name                         TEXT        NOT NULL DEFAULT '취약계층 밀집도 데이터.zip',
    ingested_at                         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (district_name)
);

COMMENT ON TABLE ref.seoul_vulnerable_population_district_snapshot IS
    '서울 25개 자치구 취약계층 밀집도 스냅샷. '
    '고령자현황(2025 Q4), 장애인현황(2024), 국민기초생활보장수급자(2024), 지하반지하주택(수집일 2026-04-03) 통합. '
    'vulnerability_score 산출 입력 feature로 사용. composite score는 이 테이블에 포함하지 않음.';

COMMENT ON COLUMN ref.seoul_vulnerable_population_district_snapshot.elderly_population_ratio IS
    'elderly_population_total / total_population (0.0~1.0). 동일 소스(고령자현황 2025 Q4) 기준.';
COMMENT ON COLUMN ref.seoul_vulnerable_population_district_snapshot.disabled_population_ratio IS
    'disabled_population_total / total_population (0.0~1.0). 분모=고령자현황 2025 Q4, 분자=장애인현황 2024 — 소스 시점 상이.';
COMMENT ON COLUMN ref.seoul_vulnerable_population_district_snapshot.basic_livelihood_recipient_ratio IS
    'basic_livelihood_recipient_total / total_population (0.0~1.0). 분모=고령자현황 2025 Q4, 분자=기초생보 2024 — 소스 시점 상이.';
COMMENT ON COLUMN ref.seoul_vulnerable_population_district_snapshot.aged_basement_household_ratio IS
    '원본 CSV 「노후 비율(%)」/100 (0.0~1.0). 이론상 aged_basement_household_count/basement_household_count 와 일치하나 '
    '원천 반올림으로 count 재계산과 소수점 차이가 날 수 있음.';

CREATE INDEX IF NOT EXISTS idx_ref_vulnerable_pop_district
    ON ref.seoul_vulnerable_population_district_snapshot (district_name);

-- ---------------------------------------------------------------------------
-- mart.seoul_vulnerable_population_district_latest
-- ---------------------------------------------------------------------------
-- ref 스냅샷에서 district-level latest/static view.
-- 점수 계산 및 feature join에 바로 사용. 25개 자치구 1:1 대응.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW mart.seoul_vulnerable_population_district_latest AS
SELECT
    district_name,
    total_population,
    elderly_population_total,
    elderly_population_ratio,
    elderly_population_korean_total,
    elderly_population_foreign_total,
    disabled_population_total,
    disabled_population_ratio,
    disabled_population_male,
    disabled_population_female,
    basic_livelihood_recipient_total,
    basic_livelihood_recipient_ratio,
    basic_livelihood_household_count,
    basement_household_count,
    aged_basement_household_count,
    aged_basement_household_ratio,
    elderly_source_label,
    elderly_source_year,
    disabled_source_year,
    basic_livelihood_source_year,
    basement_source_note,
    source_name,
    ingested_at,
    updated_at
FROM ref.seoul_vulnerable_population_district_snapshot
ORDER BY district_name;

COMMENT ON VIEW mart.seoul_vulnerable_population_district_latest IS
    '취약계층 밀집도 district-level static view. 25개 자치구, 점수 산정·모델 feature join용.';

COMMIT;
