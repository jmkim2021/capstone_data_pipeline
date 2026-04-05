from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo


KST = ZoneInfo("Asia/Seoul")


def now_kst() -> datetime:
    return datetime.now(KST)


def floor_to_10min(dt: datetime) -> datetime:
    minute = (dt.minute // 10) * 10
    return dt.replace(minute=minute, second=0, microsecond=0)


def get_latest_ultra_base_datetime(now_dt: datetime | None = None, lag_minutes: int = 10) -> datetime:
    """
    초단기실황/초단기예보용:
    현재 시각에서 lag_minutes만큼 빼고 10분 단위로 내림.
    """
    if now_dt is None:
        now_dt = now_kst()
    safe_dt = now_dt - timedelta(minutes=lag_minutes)
    return floor_to_10min(safe_dt)


def get_latest_short_base_datetime(now_dt: datetime | None = None, lag_minutes: int = 10) -> datetime:
    """
    단기예보 발표시각:
    02, 05, 08, 11, 14, 17, 20, 23시
    """
    if now_dt is None:
        now_dt = now_kst()

    safe_dt = now_dt - timedelta(minutes=lag_minutes)
    candidates = [2, 5, 8, 11, 14, 17, 20, 23]

    for hour in reversed(candidates):
        candidate = safe_dt.replace(hour=hour, minute=0, second=0, microsecond=0)
        if safe_dt >= candidate:
            return candidate

    prev_day = safe_dt - timedelta(days=1)
    return prev_day.replace(hour=23, minute=0, second=0, microsecond=0)


def fmt_date(dt: datetime) -> str:
    return dt.strftime("%Y%m%d")


def fmt_time(dt: datetime) -> str:
    return dt.strftime("%H%M")


def combine_kst(date_str: str, time_str: str) -> datetime:
    return datetime.strptime(f"{date_str}{time_str}", "%Y%m%d%H%M").replace(tzinfo=KST)