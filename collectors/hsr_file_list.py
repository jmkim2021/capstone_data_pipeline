from __future__ import annotations

from datetime import timedelta
from pathlib import Path
import sys

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.append(str(PROJECT_ROOT))

from core.config import settings
from core.db import insert_raw_hsr_request, upsert_std_hsr_file_inventory
from core.hsr_api import HSRApiError, call_hsr_file_list
from core.kma_time import now_kst


def _floor_to_5min(dt):
    minute = (dt.minute // 5) * 5
    return dt.replace(minute=minute, second=0, microsecond=0)


def main() -> None:
    requested_at = now_kst()
    base_dt = _floor_to_5min(requested_at - timedelta(minutes=settings.hsr_lag_minutes))

    try:
        response_text, lines = call_hsr_file_list(base_dt.strftime("%Y%m%d%H%M"))
        insert_raw_hsr_request([{
            "requested_at": requested_at,
            "base_datetime": base_dt,
            "http_status": 200,
            "is_success": True,
            "error_message": None,
            "response_text": response_text,
        }])

        std_rows = []
        for line in lines:
            file_name = line.rsplit("/", 1)[-1]
            std_rows.append({
                "base_datetime": base_dt,
                "file_name": file_name,
                "file_url": line,
                "requested_at": requested_at,
            })
        if std_rows:
            upsert_std_hsr_file_inventory(std_rows)

        print(
            "[hsr_file_list] "
            f"requested_at={requested_at.isoformat()} "
            f"base_dt={base_dt.isoformat()} "
            f"files={len(std_rows)}"
        )
    except HSRApiError as exc:
        message = str(exc)
        insert_raw_hsr_request([{
            "requested_at": requested_at,
            "base_datetime": base_dt,
            "http_status": 403 if "403" in message else None,
            "is_success": False,
            "error_message": message,
            "response_text": None,
        }])
        raise


if __name__ == "__main__":
    main()
