from __future__ import annotations

from contextlib import contextmanager

import psycopg2
from psycopg2.extras import Json, execute_batch

from core.config import settings


@contextmanager
def get_conn():
    conn = psycopg2.connect(
        host=settings.db_host,
        port=settings.db_port,
        dbname=settings.db_name,
        user=settings.db_user,
        password=settings.db_password,
    )
    try:
        yield conn
    finally:
        conn.close()


def _prepare_json_rows(rows: list[dict]) -> list[dict]:
    prepared_rows: list[dict] = []
    for row in rows:
        prepared_row = dict(row)
        if "response_json" in prepared_row:
            prepared_row["response_json"] = Json(prepared_row["response_json"])
        prepared_rows.append(prepared_row)
    return prepared_rows


def _execute_batch_rows(sql: str, rows: list[dict]) -> None:
    if not rows:
        return

    with get_conn() as conn:
        with conn.cursor() as cur:
            execute_batch(cur, sql, rows, page_size=settings.db_batch_size)
        conn.commit()


def insert_raw_ultra_now(rows: list[dict]) -> None:
    sql = """
    INSERT INTO raw.kma_ultra_now_raw (
        requested_at, base_date, base_time, nx, ny, category, obsr_value, response_json, created_at
    )
    VALUES (
        %(requested_at)s, %(base_date)s, %(base_time)s, %(nx)s, %(ny)s, %(category)s,
        %(obsr_value)s, %(response_json)s, NOW()
    )
    """
    _execute_batch_rows(sql, _prepare_json_rows(rows))


def insert_raw_ultra_fcst(rows: list[dict]) -> None:
    sql = """
    INSERT INTO raw.kma_ultra_fcst_raw (
        requested_at, base_date, base_time, fcst_date, fcst_time, nx, ny,
        category, fcst_value, response_json, created_at
    )
    VALUES (
        %(requested_at)s, %(base_date)s, %(base_time)s, %(fcst_date)s, %(fcst_time)s,
        %(nx)s, %(ny)s, %(category)s, %(fcst_value)s, %(response_json)s, NOW()
    )
    """
    _execute_batch_rows(sql, _prepare_json_rows(rows))


def insert_raw_short_fcst(rows: list[dict]) -> None:
    sql = """
    INSERT INTO raw.kma_short_fcst_raw (
        requested_at, base_date, base_time, fcst_date, fcst_time, nx, ny,
        category, fcst_value, response_json, created_at
    )
    VALUES (
        %(requested_at)s, %(base_date)s, %(base_time)s, %(fcst_date)s, %(fcst_time)s,
        %(nx)s, %(ny)s, %(category)s, %(fcst_value)s, %(response_json)s, NOW()
    )
    """
    _execute_batch_rows(sql, _prepare_json_rows(rows))


def upsert_std_ultra_now(rows: list[dict]) -> None:
    sql = """
    INSERT INTO std.kma_ultra_now_std (
        base_datetime, nx, ny, rain_1h_text, rain_1h_mm, rain_1h_parse_type,
        temp_c, humidity_pct, wind_speed_ms, wind_dir_deg, precip_type_code,
        requested_at, raw_batch_time, created_at
    )
    VALUES (
        %(base_datetime)s, %(nx)s, %(ny)s, %(rain_1h_text)s, %(rain_1h_mm)s, %(rain_1h_parse_type)s,
        %(temp_c)s, %(humidity_pct)s, %(wind_speed_ms)s, %(wind_dir_deg)s, %(precip_type_code)s,
        %(requested_at)s, %(raw_batch_time)s, NOW()
    )
    ON CONFLICT (base_datetime, nx, ny)
    DO UPDATE SET
        rain_1h_text = EXCLUDED.rain_1h_text,
        rain_1h_mm = EXCLUDED.rain_1h_mm,
        rain_1h_parse_type = EXCLUDED.rain_1h_parse_type,
        temp_c = EXCLUDED.temp_c,
        humidity_pct = EXCLUDED.humidity_pct,
        wind_speed_ms = EXCLUDED.wind_speed_ms,
        wind_dir_deg = EXCLUDED.wind_dir_deg,
        precip_type_code = EXCLUDED.precip_type_code,
        requested_at = EXCLUDED.requested_at,
        raw_batch_time = EXCLUDED.raw_batch_time
    """
    _execute_batch_rows(sql, rows)


def upsert_district_ultra_now(rows: list[dict]) -> None:
    sql = """
    INSERT INTO mart.seoul_district_ultra_now (
        base_datetime, district_name, rain_1h_mm, temp_c, humidity_pct,
        wind_speed_ms, wind_dir_deg, precip_type_code, source_grid_count,
        weight_sum, requested_at, raw_batch_time, created_at
    )
    VALUES (
        %(base_datetime)s, %(district_name)s, %(rain_1h_mm)s, %(temp_c)s, %(humidity_pct)s,
        %(wind_speed_ms)s, %(wind_dir_deg)s, %(precip_type_code)s, %(source_grid_count)s,
        %(weight_sum)s, %(requested_at)s, %(raw_batch_time)s, NOW()
    )
    ON CONFLICT (base_datetime, district_name)
    DO UPDATE SET
        rain_1h_mm = EXCLUDED.rain_1h_mm,
        temp_c = EXCLUDED.temp_c,
        humidity_pct = EXCLUDED.humidity_pct,
        wind_speed_ms = EXCLUDED.wind_speed_ms,
        wind_dir_deg = EXCLUDED.wind_dir_deg,
        precip_type_code = EXCLUDED.precip_type_code,
        source_grid_count = EXCLUDED.source_grid_count,
        weight_sum = EXCLUDED.weight_sum,
        requested_at = EXCLUDED.requested_at,
        raw_batch_time = EXCLUDED.raw_batch_time
    """
    _execute_batch_rows(sql, rows)


def upsert_district_ultra_fcst(rows: list[dict]) -> None:
    sql = """
    INSERT INTO mart.seoul_district_ultra_fcst (
        base_datetime, forecast_datetime, lead_minutes, district_name,
        forecast_temp_c, forecast_humidity_pct, forecast_precip_mm_num,
        forecast_wind_speed_ms, forecast_sky_code, forecast_precip_type_code,
        source_grid_count, weight_sum, requested_at, created_at
    )
    VALUES (
        %(base_datetime)s, %(forecast_datetime)s, %(lead_minutes)s, %(district_name)s,
        %(forecast_temp_c)s, %(forecast_humidity_pct)s, %(forecast_precip_mm_num)s,
        %(forecast_wind_speed_ms)s, %(forecast_sky_code)s, %(forecast_precip_type_code)s,
        %(source_grid_count)s, %(weight_sum)s, %(requested_at)s, NOW()
    )
    ON CONFLICT (base_datetime, forecast_datetime, district_name)
    DO UPDATE SET
        lead_minutes = EXCLUDED.lead_minutes,
        forecast_temp_c = EXCLUDED.forecast_temp_c,
        forecast_humidity_pct = EXCLUDED.forecast_humidity_pct,
        forecast_precip_mm_num = EXCLUDED.forecast_precip_mm_num,
        forecast_wind_speed_ms = EXCLUDED.forecast_wind_speed_ms,
        forecast_sky_code = EXCLUDED.forecast_sky_code,
        forecast_precip_type_code = EXCLUDED.forecast_precip_type_code,
        source_grid_count = EXCLUDED.source_grid_count,
        weight_sum = EXCLUDED.weight_sum,
        requested_at = EXCLUDED.requested_at
    """
    _execute_batch_rows(sql, rows)


def upsert_std_ultra_fcst(rows: list[dict]) -> None:
    sql = """
    INSERT INTO std.kma_ultra_fcst_std (
        base_datetime, forecast_datetime, lead_minutes, nx, ny,
        forecast_temp_c, forecast_humidity_pct, forecast_sky_code,
        forecast_precip_type_code, forecast_precip_mm_text,
        forecast_precip_mm_num, forecast_precip_parse_type,
        forecast_wind_speed_ms, requested_at, created_at
    )
    VALUES (
        %(base_datetime)s, %(forecast_datetime)s, %(lead_minutes)s, %(nx)s, %(ny)s,
        %(forecast_temp_c)s, %(forecast_humidity_pct)s, %(forecast_sky_code)s,
        %(forecast_precip_type_code)s, %(forecast_precip_mm_text)s,
        %(forecast_precip_mm_num)s, %(forecast_precip_parse_type)s,
        %(forecast_wind_speed_ms)s, %(requested_at)s, NOW()
    )
    ON CONFLICT (base_datetime, forecast_datetime, nx, ny)
    DO UPDATE SET
        lead_minutes = EXCLUDED.lead_minutes,
        forecast_temp_c = EXCLUDED.forecast_temp_c,
        forecast_humidity_pct = EXCLUDED.forecast_humidity_pct,
        forecast_sky_code = EXCLUDED.forecast_sky_code,
        forecast_precip_type_code = EXCLUDED.forecast_precip_type_code,
        forecast_precip_mm_text = EXCLUDED.forecast_precip_mm_text,
        forecast_precip_mm_num = EXCLUDED.forecast_precip_mm_num,
        forecast_precip_parse_type = EXCLUDED.forecast_precip_parse_type,
        forecast_wind_speed_ms = EXCLUDED.forecast_wind_speed_ms,
        requested_at = EXCLUDED.requested_at
    """
    _execute_batch_rows(sql, rows)


def upsert_district_short_fcst(rows: list[dict]) -> None:
    sql = """
    INSERT INTO mart.seoul_district_short_fcst (
        base_datetime, forecast_datetime, lead_hours, district_name,
        forecast_temp_c, forecast_humidity_pct, forecast_pop_pct,
        forecast_precip_mm_num, forecast_wind_speed_ms, forecast_sky_code,
        forecast_precip_type_code, source_grid_count, weight_sum,
        requested_at, created_at
    )
    VALUES (
        %(base_datetime)s, %(forecast_datetime)s, %(lead_hours)s, %(district_name)s,
        %(forecast_temp_c)s, %(forecast_humidity_pct)s, %(forecast_pop_pct)s,
        %(forecast_precip_mm_num)s, %(forecast_wind_speed_ms)s, %(forecast_sky_code)s,
        %(forecast_precip_type_code)s, %(source_grid_count)s, %(weight_sum)s,
        %(requested_at)s, NOW()
    )
    ON CONFLICT (base_datetime, forecast_datetime, district_name)
    DO UPDATE SET
        lead_hours = EXCLUDED.lead_hours,
        forecast_temp_c = EXCLUDED.forecast_temp_c,
        forecast_humidity_pct = EXCLUDED.forecast_humidity_pct,
        forecast_pop_pct = EXCLUDED.forecast_pop_pct,
        forecast_precip_mm_num = EXCLUDED.forecast_precip_mm_num,
        forecast_wind_speed_ms = EXCLUDED.forecast_wind_speed_ms,
        forecast_sky_code = EXCLUDED.forecast_sky_code,
        forecast_precip_type_code = EXCLUDED.forecast_precip_type_code,
        source_grid_count = EXCLUDED.source_grid_count,
        weight_sum = EXCLUDED.weight_sum,
        requested_at = EXCLUDED.requested_at
    """
    _execute_batch_rows(sql, rows)


def upsert_std_short_fcst(rows: list[dict]) -> None:
    sql = """
    INSERT INTO std.kma_short_fcst_std (
        base_datetime, forecast_datetime, lead_hours, nx, ny,
        forecast_temp_c, forecast_humidity_pct, forecast_pop_pct,
        forecast_precip_mm_text, forecast_precip_mm_num,
        forecast_precip_parse_type, forecast_sky_code,
        forecast_precip_type_code, forecast_wind_speed_ms,
        requested_at, created_at
    )
    VALUES (
        %(base_datetime)s, %(forecast_datetime)s, %(lead_hours)s, %(nx)s, %(ny)s,
        %(forecast_temp_c)s, %(forecast_humidity_pct)s, %(forecast_pop_pct)s,
        %(forecast_precip_mm_text)s, %(forecast_precip_mm_num)s,
        %(forecast_precip_parse_type)s, %(forecast_sky_code)s,
        %(forecast_precip_type_code)s, %(forecast_wind_speed_ms)s,
        %(requested_at)s, NOW()
    )
    ON CONFLICT (base_datetime, forecast_datetime, nx, ny)
    DO UPDATE SET
        lead_hours = EXCLUDED.lead_hours,
        forecast_temp_c = EXCLUDED.forecast_temp_c,
        forecast_humidity_pct = EXCLUDED.forecast_humidity_pct,
        forecast_pop_pct = EXCLUDED.forecast_pop_pct,
        forecast_precip_mm_text = EXCLUDED.forecast_precip_mm_text,
        forecast_precip_mm_num = EXCLUDED.forecast_precip_mm_num,
        forecast_precip_parse_type = EXCLUDED.forecast_precip_parse_type,
        forecast_sky_code = EXCLUDED.forecast_sky_code,
        forecast_precip_type_code = EXCLUDED.forecast_precip_type_code,
        forecast_wind_speed_ms = EXCLUDED.forecast_wind_speed_ms,
        requested_at = EXCLUDED.requested_at
    """
    _execute_batch_rows(sql, rows)


def insert_raw_seoul_rainfall(rows: list[dict]) -> None:
    sql = """
    INSERT INTO raw.seoul_rainfall_raw (
        requested_at, observed_at, station_code, response_json, created_at
    )
    VALUES (
        %(requested_at)s, %(observed_at)s, %(station_code)s, %(response_json)s, NOW()
    )
    """
    _execute_batch_rows(sql, _prepare_json_rows(rows))


def upsert_std_seoul_rainfall(rows: list[dict]) -> None:
    sql = """
    INSERT INTO std.seoul_rainfall_std (
        observed_at, station_code, station_name, district_code, district_name,
        rain_10m_mm, requested_at, created_at
    )
    VALUES (
        %(observed_at)s, %(station_code)s, %(station_name)s, %(district_code)s, %(district_name)s,
        %(rain_10m_mm)s, %(requested_at)s, NOW()
    )
    ON CONFLICT (observed_at, station_code)
    DO UPDATE SET
        station_name = EXCLUDED.station_name,
        district_code = EXCLUDED.district_code,
        district_name = EXCLUDED.district_name,
        rain_10m_mm = EXCLUDED.rain_10m_mm,
        requested_at = EXCLUDED.requested_at
    """
    _execute_batch_rows(sql, rows)


def upsert_mart_seoul_rainfall_district_latest(rows: list[dict]) -> None:
    sql = """
    INSERT INTO mart.seoul_rainfall_district_latest (
        observed_at, district_name, station_count, avg_rain_10m_mm,
        max_rain_10m_mm, requested_at, created_at
    )
    VALUES (
        %(observed_at)s, %(district_name)s, %(station_count)s, %(avg_rain_10m_mm)s,
        %(max_rain_10m_mm)s, %(requested_at)s, NOW()
    )
    ON CONFLICT (observed_at, district_name)
    DO UPDATE SET
        station_count = EXCLUDED.station_count,
        avg_rain_10m_mm = EXCLUDED.avg_rain_10m_mm,
        max_rain_10m_mm = EXCLUDED.max_rain_10m_mm,
        requested_at = EXCLUDED.requested_at
    """
    _execute_batch_rows(sql, rows)


def insert_raw_seoul_river_stage(rows: list[dict]) -> None:
    sql = """
    INSERT INTO raw.seoul_river_stage_raw (
        requested_at, observed_at, station_code, response_json, created_at
    )
    VALUES (
        %(requested_at)s, %(observed_at)s, %(station_code)s, %(response_json)s, NOW()
    )
    """
    _execute_batch_rows(sql, _prepare_json_rows(rows))


def upsert_std_seoul_river_stage(rows: list[dict]) -> None:
    sql = """
    INSERT INTO std.seoul_river_stage_std (
        observed_at, station_code, station_name, river_name, district_code, district_name,
        water_level_m, embankment_height_m, plan_flood_level_m, riverbed_height_m,
        control_level_m, requested_at, server_stored_at, created_at
    )
    VALUES (
        %(observed_at)s, %(station_code)s, %(station_name)s, %(river_name)s, %(district_code)s, %(district_name)s,
        %(water_level_m)s, %(embankment_height_m)s, %(plan_flood_level_m)s, %(riverbed_height_m)s,
        %(control_level_m)s, %(requested_at)s, %(server_stored_at)s, NOW()
    )
    ON CONFLICT (observed_at, station_code)
    DO UPDATE SET
        station_name = EXCLUDED.station_name,
        river_name = EXCLUDED.river_name,
        district_code = EXCLUDED.district_code,
        district_name = EXCLUDED.district_name,
        water_level_m = EXCLUDED.water_level_m,
        embankment_height_m = EXCLUDED.embankment_height_m,
        plan_flood_level_m = EXCLUDED.plan_flood_level_m,
        riverbed_height_m = EXCLUDED.riverbed_height_m,
        control_level_m = EXCLUDED.control_level_m,
        requested_at = EXCLUDED.requested_at,
        server_stored_at = EXCLUDED.server_stored_at
    """
    _execute_batch_rows(sql, rows)


def upsert_mart_seoul_river_stage_latest(rows: list[dict]) -> None:
    sql = """
    INSERT INTO mart.seoul_river_stage_district_latest (
        observed_minute, district_name, station_count, avg_water_level_m,
        max_water_level_m, max_control_level_m, requested_at, created_at
    )
    VALUES (
        %(observed_minute)s, %(district_name)s, %(station_count)s, %(avg_water_level_m)s,
        %(max_water_level_m)s, %(max_control_level_m)s, %(requested_at)s, NOW()
    )
    ON CONFLICT (observed_minute, district_name)
    DO UPDATE SET
        station_count = EXCLUDED.station_count,
        avg_water_level_m = EXCLUDED.avg_water_level_m,
        max_water_level_m = EXCLUDED.max_water_level_m,
        max_control_level_m = EXCLUDED.max_control_level_m,
        requested_at = EXCLUDED.requested_at
    """
    _execute_batch_rows(sql, rows)


def insert_raw_hsr_request(rows: list[dict]) -> None:
    sql = """
    INSERT INTO raw.kma_hsr_request_raw (
        requested_at, base_datetime, http_status, is_success,
        error_message, response_text, created_at
    )
    VALUES (
        %(requested_at)s, %(base_datetime)s, %(http_status)s, %(is_success)s,
        %(error_message)s, %(response_text)s, NOW()
    )
    """
    _execute_batch_rows(sql, rows)


def upsert_std_hsr_file_inventory(rows: list[dict]) -> None:
    sql = """
    INSERT INTO std.kma_hsr_file_inventory_std (
        base_datetime, file_name, file_url, requested_at, created_at
    )
    VALUES (
        %(base_datetime)s, %(file_name)s, %(file_url)s, %(requested_at)s, NOW()
    )
    ON CONFLICT (base_datetime, file_name)
    DO UPDATE SET
        file_url = EXCLUDED.file_url,
        requested_at = EXCLUDED.requested_at
    """
    _execute_batch_rows(sql, rows)


def insert_raw_hsr_area(rows: list[dict]) -> None:
    sql = """
    INSERT INTO raw.kma_hsr_area_raw (
        requested_at, base_datetime, district_code, district_name, comp_type,
        data_type_cd, http_status, result_code, is_success, error_message,
        response_json, created_at
    )
    VALUES (
        %(requested_at)s, %(base_datetime)s, %(district_code)s, %(district_name)s, %(comp_type)s,
        %(data_type_cd)s, %(http_status)s, %(result_code)s, %(is_success)s, %(error_message)s,
        %(response_json)s, NOW()
    )
    """
    _execute_batch_rows(sql, _prepare_json_rows(rows))


def upsert_std_hsr_area_district(rows: list[dict]) -> None:
    sql = """
    INSERT INTO std.kma_hsr_area_district_std (
        base_datetime, district_code, district_name, comp_type, data_type_cd,
        lon, lat, unit, value_numeric, raw_value_text, is_no_echo, requested_at, created_at
    )
    VALUES (
        %(base_datetime)s, %(district_code)s, %(district_name)s, %(comp_type)s, %(data_type_cd)s,
        %(lon)s, %(lat)s, %(unit)s, %(value_numeric)s, %(raw_value_text)s, %(is_no_echo)s,
        %(requested_at)s, NOW()
    )
    ON CONFLICT (base_datetime, district_code, comp_type, data_type_cd)
    DO UPDATE SET
        district_name = EXCLUDED.district_name,
        lon = EXCLUDED.lon,
        lat = EXCLUDED.lat,
        unit = EXCLUDED.unit,
        value_numeric = EXCLUDED.value_numeric,
        raw_value_text = EXCLUDED.raw_value_text,
        is_no_echo = EXCLUDED.is_no_echo,
        requested_at = EXCLUDED.requested_at
    """
    _execute_batch_rows(sql, rows)