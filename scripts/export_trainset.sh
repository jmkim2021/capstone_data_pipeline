#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$PROJECT_ROOT/data/trainset"

if [[ -f "$PROJECT_ROOT/.env" ]]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-weather}"
DB_USER="${DB_USER:-postgres}"

mkdir -p "$OUT_DIR"

ts="$(date +"%Y-%m-%d_%H%M")"

export_file() {
  local split="$1"
  local out="$OUT_DIR/${split}_${ts}.csv"

  psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 \
    -c "\\copy (SELECT * FROM ml.seoul_heavyrain_${split} ORDER BY base_datetime, district_name) TO '${out}' CSV HEADER"

  echo "wrote: $out" >&2
}

export_file train
export_file valid
export_file test

