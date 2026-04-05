# 데이터 파이프라인 (문서 + SQL + 데이터)

GitHub로 넘길 때 아래 세 덩어리로 나누면 팀 온보딩이 수월합니다.

**원칙:** **`.env`와 `data/` 실데이터는 Git에 올리지 않습니다.** 저장소에는 스크립트·SQL·문서와 `data/*.example.*` 정도만 두고, 키·격자 CSV·DB 덤프는 **별도로** 팀원에게 전달합니다.

## 1. 문서 (이 파일 + README)

- **README.md**: 설치·실행 요약.
- **본 문서**: 스키마 적용 순서, 수집 경로, 데이터 공유 옵션.

## 2. SQL (`sql/`)

### 2.1 기본 적용 순서 (번호순 DDL·뷰)

운영·수집에 필요한 코어에 가까운 파일부터 번호가 잡혀 있습니다. `psql` 또는 마이그레이션 도구로 **아래 순서대로** 적용하는 것을 권장합니다.

| 순서 | 파일 | 요약 |
|------|------|------|
| 1 | `000_kma_base_tables.sql` | 기상청 수집 원천·공통 기반 |
| 2 | `001_kma_std_columns.sql` | 표준 컬럼 정의 |
| 3 | `002_seoul_district_grid_map.sql` | 자치구–격자 매핑 |
| 4 | `003_seoul_district_ultra_now.sql` | 초단기실황 구 단위 |
| 5 | `004_kma_collection_status.sql` | 수집 상태 |
| 6 | `005_district_forecast_tables.sql` | 구 단위 예보 관련 |
| 7 | `006_district_weather_views.sql` | 구 단위 뷰 |
| 8 | `007_seoul_rain_gauge_tables.sql` | 서울 강수량계 |
| 9 | `008_seoul_flood_trace_tables.sql` | 침수흔적 등 |
| 10 | `009_seoul_disaster_risk_zone_tables.sql` | 재해위험지구 |
| 11 | `010_external_realtime_sources.sql` | 외부 실시간 소스 |
| 12 | `011_district_flood_features.sql` | 침수 피처 |
| 13 | `012_district_model_features.sql` | 모델 피처(초기) |
| 14 | `013_seoul_aws_district_tables.sql` | AWS 구 단위 |
| 15 | `014_seoul_aws_views.sql` | AWS 뷰 |
| 16 | `015_kma_hsr_area_tables.sql` | 강수영역(HSR) API 적재 |
| 17 | `022_seoul_construction_progress_tables.sql` | 건설공사 추진 현황 |
| 18 | `023_seoul_living_population_korean_district_tables.sql` | 생활인구(내국인) 구 단위 |
| 19 | `024_seoul_living_population_korean_operational.sql` | 생활인구 운영 보조 |
| 20 | `025_seoul_district_worker_stats.sql` | 구 단위 근로자 통계 |
| 21 | `026_seoul_vulnerable_population_tables.sql` | 취약인구 |
| 22 | `027_seoul_district_model_features_v2.sql` | 모델 피처 v2 |
| 23 | `028_operational_reliability.sql` | 운영 신뢰도 |

### 2.2 분석·모델·검증용 (필요 시)

강수 라벨·학습용 마트·검증 게이트 등은 **프로젝트 단계에 따라** 선택 적용합니다. 파일명에 `heavyrain`, `modelready`, `ml_`, `validation`, `diagnostics` 가 포함된 SQL을 참고하세요.

### 2.3 `verify_*.sql`

운영 점검·감사용 쿼리입니다. 배포 후 주기 실행 또는 PR 전 로컬 검증에 사용합니다.

## 3. 수집기·ingest 매핑

### 3.1 `collectors/` (스케줄로 돌리기 좋은 항목)

| 스크립트 | 대략적 역할 | 필요한 환경 변수(예) |
|----------|-------------|----------------------|
| `ultra_now.py` | 초단기실황 | `KMA_SERVICE_KEY` |
| `ultra_fcst.py` | 초단기예보 | 동일 |
| `short_fcst.py` | 단기예보 | 동일 |
| `seoul_rainfall.py` | 서울 강우 | `SEOUL_RAINFALL_API_KEY` |
| `seoul_river_stage.py` | 하천 수위 | `SEOUL_RIVER_API_KEY` |
| `hsr_district.py` | 레이더 강수영역 | `HSR_API_AUTH_KEY` 등 |
| `hsr_file_list.py` | 레이더 파일 목록 | 동일 |
| `seoul_construction_progress.py` | 건설공사 | `SEOUL_CONSTRUCTION_API_KEY` |
| `seoul_living_population_korean_district_hourly.py` | 생활인구 | `SEOUL_OPEN_API_KEY` |

공통: `DB_*`, 격자 파일 `DISTRICT_GRID_MAPPING_PATH` 또는 `data/seoul_district_grids.csv`.

### 3.2 `ingest/` (파일·수동 배치)

| 스크립트 | 용도 |
|----------|------|
| `portal_ultra_now_folder_loader.py` | 포털에서 받은 초단기실황 CSV 폴더 적재 |
| `portal_ultra_now_representative_dong.py` | 대표 동 단위 처리 |
| `seoul_aws_district.py` | AWS 구 단위 소스 |
| `seoul_rain_gauge_station.py` | 강수량계 엑셀/메타 |
| `seoul_flood_trace.py` | 침수흔적 지오데이터 |
| `seoul_disaster_risk_zone.py` | 재해위험지구 |
| `seoul_vulnerable_population_district.py` | 취약인구 |
| `seoul_district_worker_stats.py` | 근로자 통계 |

각 스크립트의 `--help` 를 실행해 입력 경로·옵션을 확인합니다.

## 4. 데이터 공유 (Git에 안 올리는 것이 좋은 것들)

대용량·개인정보·라이선스가 애매한 원본은 **저장소 밖**에서 공유합니다.

권장 방식:

1. **스키마 + 샘플**
   - `data/seoul_district_grids.example.csv` 처럼 형식만 포함.
   - 실제 격자 CSV는 팀 내부 드라이브·암호화 공유.

2. **DB 덤프**
   - `pg_dump -Fc` 로 스키마+데이터 또는 스키마만.
   - 민감 컬럼은 마스킹 후 덤프.

3. **이 저장소의 export 스크립트**
   - `scripts/export_*.py`, `scripts/export_trainset.sh` 등으로 모델용 CSV/패키지 생성 후 별도 채널로 전달.

`.gitignore` 에 `data/*`(예시 제외), `.env`, 로컬 대용량 폴더(예: `서울 초단기실황/`), `handoff/`, `exports/` 등이 포함되어 있습니다.

## 5. 중복·갈래 SQL (`017`, `018`, `020`, `021` 등)

같은 번대에 여러 파일이 있으면 **실험/버전/재추출** 이력일 수 있습니다. 운영 DB에는 프로젝트에서 확정한 버전만 적용하고, 나머지는 문서나 이슈에 “선택 적용”으로 표기하는 것을 권장합니다.
