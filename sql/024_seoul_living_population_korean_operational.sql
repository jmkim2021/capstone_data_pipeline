BEGIN;

-- ref 컬럼 의미(운영/모델 해석용). OA-15439 JSON에 별도 공개일 필드가 없음.
COMMENT ON COLUMN ref.seoul_living_population_korean_district_hourly.base_date IS
    '집계·관측 기준일(STDR_DE_ID). 실제 데이터 시점의 날짜 축.';
COMMENT ON COLUMN ref.seoul_living_population_korean_district_hourly.base_hour IS
    '집계·관측 기준 시각(0–23, TMZON_PD_SE). base_date와 함께 실제 데이터 시점.';
COMMENT ON COLUMN ref.seoul_living_population_korean_district_hourly.source_date IS
    '원천 응답의 STDR_DE_ID 캘린더 일자. 별도 공개일 필드가 없어 현재는 base_date와 동일.';
COMMENT ON COLUMN ref.seoul_living_population_korean_district_hourly.requested_date IS
    '수집 잡이 의도한 요청일(daily의 --target-date 또는 backfill 루프 상의 해당일). lookback 시 base_date와 다를 수 있음.';
COMMENT ON COLUMN ref.seoul_living_population_korean_district_hourly.korean_population IS
    '내국인 생활인구 proxy(TOT_LVPOP_CO). 총 생활인구·외국인 포함 수치가 아님.';

-- 시계열 as-of 조인·lag 분석용 (KST 벽시계 시각 → timestamptz)
CREATE OR REPLACE VIEW mart.seoul_living_population_korean_hourly_observed_at AS
SELECT
    h.base_date,
    h.base_hour,
    h.district_code,
    h.district_name,
    h.korean_population,
    h.source_date,
    h.source_name,
    h.requested_date,
    h.ingested_at,
    h.updated_at,
    ((h.base_date + (h.base_hour * INTERVAL '1 hour')) AT TIME ZONE 'Asia/Seoul') AS observed_at_timestamptz
FROM ref.seoul_living_population_korean_district_hourly h;

COMMENT ON VIEW mart.seoul_living_population_korean_hourly_observed_at IS
    'ref 시계열에 observed_at_timestamptz를 붙인 디버깅·검증용 뷰. realtime 조인은 016 뷰에서 LATERAL as-of로 수행.';

COMMIT;
