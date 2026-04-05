# 서울·기상 데이터 수집 파이프라인

PostgreSQL에 적재하는 **API 수집기**, **배치 적재(ingest)**, **DDL·뷰·검증 SQL**을 한 저장소에 모아 두었습니다.

**Git에는 코드·SQL·문서만** 올리는 것을 권장합니다. **`.env`**(API 키·DB 접속)와 **`data/`** 아래 실제 격자 CSV 등 참조 데이터는 **저장소가 아니라 팀 내부 채널**(암호 공유 드라이브, `pg_dump`, export 산출물 등)로 넘기면 됩니다. 저장소에는 `data/*.example.*` 형식만 두어 형식을 알려 줍니다.

## 빠른 시작

1. Python 3.11+ 권장, PostgreSQL 준비.
2. `cp .env.example .env` 후 API·DB 값 입력 (`.env`는 Git에 올리지 않음).
3. `pip install -r requirements.txt`
4. 스키마는 `sql/`을 번호 순으로 적용 — 상세는 [docs/DATA_PIPELINE.md](docs/DATA_PIPELINE.md).
5. 격자 매핑: 팀에서 받은 `data/seoul_district_grids.csv`를 두거나, 형식은 저장소의 `data/seoul_district_grids.example.csv`를 참고해 동일 파일명으로 만듭니다.

## 디렉터리 요약

| 경로 | 역할 |
|------|------|
| `collectors/` | 주기 실행용 API 수집 (기상청·서울시·레이더 등) |
| `ingest/` | 파일·포털 다운로드 등 일회/배치 적재 |
| `core/` | DB 연결, API 클라이언트, 격자·집계 공통 로직 |
| `sql/` | 테이블·뷰·운영 검증·모델용 SQL |
| `scripts/` | 보내기·패키징·`run_collector.sh` |
| `data/` | 로컬 전용 참조 파일(격자 CSV 등). Git에는 예시만, 실파일은 팀에 따로 전달 |

## 수집기 실행 예시

```bash
./scripts/run_collector.sh ultra_now
```

환경 파일 위치를 바꿀 때: `ENV_FILE=/path/to/.env ./scripts/run_collector.sh ultra_fcst`

내장 Postgres를 쓰는 경우에만 `PG_CTL_BIN`, `POSTGRES_DATA_DIR`, `PG_ISREADY_BIN`을 설정 (선택).

## 문서

- [데이터 파이프라인 상세](docs/DATA_PIPELINE.md) — SQL 적용 순서, 수집기·ingest 매핑, 데이터 공유 방법
- [macOS launchd 예시](docs/deployment-launchd.example.md) — 로컬 cron 대체 (경로는 본인 환경에 맞게 수정)

## 보안

- API 키·DB 비밀번호는 `.env`에만 두고, 예시는 `.env.example`의 빈 값을 유지합니다.
- 이전에 `.env.example` 등에 키가 들어갔다면 **키 회전(재발급)** 을 권장합니다.
