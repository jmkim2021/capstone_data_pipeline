#!/usr/bin/env bash
# 저장소 루트 기준으로 수집기 실행. 팀원은 PYTHONPATH·.env 경로를 맞추면 됩니다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COLLECTOR_NAME="${1:-}"

if [[ -z "$COLLECTOR_NAME" ]]; then
    echo "usage: $0 <collector_name> [args...]" >&2
    echo "collectors: ultra_now, ultra_fcst, short_fcst, seoul_rainfall, seoul_river_stage," >&2
    echo "            hsr_district, seoul_construction_progress, seoul_living_population_korean_district_hourly" >&2
    exit 1
fi

shift

case "$COLLECTOR_NAME" in
    ultra_now|ultra_fcst|short_fcst|seoul_rainfall|seoul_river_stage|hsr_district|seoul_construction_progress|seoul_living_population_korean_district_hourly)
        ;;
    *)
        echo "unsupported collector: $COLLECTOR_NAME" >&2
        exit 1
        ;;
esac

ENV_FILE="${ENV_FILE:-$PROJECT_ROOT/.env}"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
fi

# 선택: 내장 Postgres 등 커스텀 런타임 (미설정이면 시스템 PostgreSQL 가정)
if [[ -n "${PG_CTL_BIN:-}" && -n "${POSTGRES_DATA_DIR:-}" ]]; then
    PG_ISREADY_BIN="${PG_ISREADY_BIN:-$(dirname "$PG_CTL_BIN")/pg_isready}"
    if ! "$PG_ISREADY_BIN" -h "${DB_HOST:-localhost}" -p "${DB_PORT:-5432}" >/dev/null 2>&1; then
        "$PG_CTL_BIN" -D "$POSTGRES_DATA_DIR" -l "$PROJECT_ROOT/.postgres.log" start
    fi
fi

PYTHON_BIN="${PYTHON_BIN:-python3}"
export PYTHONPATH="$PROJECT_ROOT"

exec "$PYTHON_BIN" "$PROJECT_ROOT/collectors/$COLLECTOR_NAME.py" "$@"
