DROP VIEW IF EXISTS mart.seoul_district_model_features CASCADE;

CREATE VIEW mart.seoul_district_model_features AS
WITH weather AS (
    SELECT
        product_type,
        district_name,
        base_datetime,
        target_datetime,
        lead_minutes,
        precip_mm,
        temp_c,
        humidity_pct,
        pop_pct,
        wind_speed_ms,
        sky_code,
        precip_type_code,
        requested_at AS weather_requested_at
    FROM mart.seoul_district_weather_timeline
),
static_features AS (
    SELECT
        district_name,
        rain_gauge_current_count,
        flood_trace_count_2023,
        flood_trace_count_2024,
        flood_trace_count_2025,
        (flood_trace_count_2023 + flood_trace_count_2024 + flood_trace_count_2025) AS flood_trace_count_total,
        flooded_area_sqm_2023,
        flooded_area_sqm_2024,
        flooded_area_sqm_2025,
        (flooded_area_sqm_2023 + flooded_area_sqm_2024 + flooded_area_sqm_2025) AS flooded_area_sqm_total,
        disaster_risk_zone_count,
        disaster_risk_zone_in_progress_count,
        disaster_risk_zone_expired_count
    FROM mart.seoul_district_flood_features
)
SELECT
    w.product_type,
    w.district_name,
    w.base_datetime,
    w.target_datetime,
    w.lead_minutes,
    w.precip_mm,
    w.temp_c,
    w.humidity_pct,
    w.pop_pct,
    w.wind_speed_ms,
    w.sky_code,
    w.precip_type_code,
    w.weather_requested_at,

    rf.observed_at AS rainfall_observed_at,
    CASE
        WHEN rf.observed_at IS NULL THEN NULL
        ELSE ROUND(EXTRACT(EPOCH FROM (w.base_datetime - rf.observed_at)) / 60.0, 2)
    END AS rainfall_lag_minutes,
    rf.station_count AS rainfall_station_count,
    rf.avg_rain_10m_mm,
    rf.max_rain_10m_mm,

    rv.observed_minute AS river_observed_at,
    CASE
        WHEN rv.observed_minute IS NULL THEN NULL
        ELSE ROUND(EXTRACT(EPOCH FROM (w.base_datetime - rv.observed_minute)) / 60.0, 2)
    END AS river_lag_minutes,
    rv.station_count AS river_station_count,
    rv.avg_water_level_m,
    rv.max_water_level_m,
    rv.max_control_level_m,

    hsr.hsr_observed_at,
    CASE
        WHEN hsr.hsr_observed_at IS NULL THEN NULL
        ELSE ROUND(EXTRACT(EPOCH FROM (w.base_datetime - hsr.hsr_observed_at)) / 60.0, 2)
    END AS hsr_lag_minutes,
    hsr.hsr_comp_type,
    hsr.hsr_data_type_cd,
    hsr.hsr_value_numeric,
    hsr.hsr_unit,
    hsr.hsr_is_no_echo,

    COALESCE(aws_own.observed_at, aws_neigh.observed_at) AS aws_observed_at,
    CASE
        WHEN COALESCE(aws_own.observed_at, aws_neigh.observed_at) IS NULL THEN NULL
        ELSE ROUND(
            EXTRACT(EPOCH FROM (w.base_datetime - COALESCE(aws_own.observed_at, aws_neigh.observed_at))) / 60.0,
            2
        )
    END AS aws_lag_minutes,
    COALESCE(aws_own.temp_c,              aws_neigh.temp_c)              AS aws_temp_c,
    COALESCE(aws_own.wind_dir_deg,        aws_neigh.wind_dir_deg)        AS aws_wind_dir_deg,
    COALESCE(aws_own.wind_speed_ms,       aws_neigh.wind_speed_ms)       AS aws_wind_speed_ms,
    COALESCE(aws_own.precip_mm,           aws_neigh.precip_mm)           AS aws_precip_mm,
    COALESCE(aws_own.local_pressure_hpa,  aws_neigh.local_pressure_hpa)  AS aws_local_pressure_hpa,
    COALESCE(aws_own.sea_level_pressure_hpa, aws_neigh.sea_level_pressure_hpa) AS aws_sea_level_pressure_hpa,
    COALESCE(aws_own.humidity_pct,        aws_neigh.humidity_pct)        AS aws_humidity_pct,
    COALESCE(aws_own.solar_radiation_mj_m2, aws_neigh.solar_radiation_mj_m2) AS aws_solar_radiation_mj_m2,
    COALESCE(aws_own.sunshine_hr,         aws_neigh.sunshine_hr)         AS aws_sunshine_hr,
    CASE
        WHEN COALESCE(aws_own.observed_at, aws_neigh.observed_at) IS NULL THEN 1
        ELSE 0
    END AS aws_missing_flag,
    (aws_own.observed_at IS NULL AND aws_neigh.observed_at IS NOT NULL) AS aws_neighbor_imputed,

    sf.rain_gauge_current_count,
    sf.flood_trace_count_2023,
    sf.flood_trace_count_2024,
    sf.flood_trace_count_2025,
    sf.flood_trace_count_total,
    sf.flooded_area_sqm_2023,
    sf.flooded_area_sqm_2024,
    sf.flooded_area_sqm_2025,
    sf.flooded_area_sqm_total,
    sf.disaster_risk_zone_count,
    sf.disaster_risk_zone_in_progress_count,
    sf.disaster_risk_zone_expired_count
FROM weather w
LEFT JOIN LATERAL (
    SELECT
        observed_at,
        station_count,
        avg_rain_10m_mm,
        max_rain_10m_mm
    FROM mart.seoul_rainfall_district_latest
    WHERE district_name = w.district_name
      AND observed_at <= w.base_datetime
    ORDER BY observed_at DESC
    LIMIT 1
) rf ON TRUE
LEFT JOIN LATERAL (
    SELECT
        observed_minute,
        station_count,
        avg_water_level_m,
        max_water_level_m,
        max_control_level_m
    FROM mart.seoul_river_stage_district_latest
    WHERE district_name = w.district_name
      AND observed_minute <= w.base_datetime
    ORDER BY observed_minute DESC
    LIMIT 1
) rv ON TRUE
LEFT JOIN LATERAL (
    SELECT
        base_datetime AS hsr_observed_at,
        comp_type AS hsr_comp_type,
        data_type_cd AS hsr_data_type_cd,
        value_numeric AS hsr_value_numeric,
        unit AS hsr_unit,
        is_no_echo AS hsr_is_no_echo
    FROM std.kma_hsr_area_district_std
    WHERE district_name = w.district_name
      AND comp_type = 'CPP'
      AND data_type_cd = 'CZ'
      AND base_datetime <= w.base_datetime
    ORDER BY base_datetime DESC
    LIMIT 1
) hsr ON TRUE
LEFT JOIN LATERAL (
    SELECT
        observed_at,
        temp_c,
        wind_dir_deg,
        wind_speed_ms,
        precip_mm,
        local_pressure_hpa,
        sea_level_pressure_hpa,
        humidity_pct,
        solar_radiation_mj_m2,
        sunshine_hr
    FROM mart.seoul_aws_district_timeline
    WHERE district_name = w.district_name
      AND observed_at <= w.base_datetime
    ORDER BY observed_at DESC
    LIMIT 1
) aws_own ON TRUE
LEFT JOIN LATERAL (
    -- 종로구: 자체 AWS 원천 부재 → meta.seoul_district_grid_map 상 종로구 격자와
    -- Chebyshev 거리 ≤ 1인 타 구(자기 제외)마다 base_datetime 이전 최신 1건을 뽑아 평균.
    -- 이웃 집합은 격자표(CSV/017) 갱신 시 자동 반영된다.
    SELECT
        MAX(t.observed_at) AS observed_at,
        AVG(t.temp_c)::double precision AS temp_c,
        AVG(t.wind_dir_deg)::double precision AS wind_dir_deg,
        AVG(t.wind_speed_ms)::double precision AS wind_speed_ms,
        AVG(t.precip_mm)::double precision AS precip_mm,
        AVG(t.local_pressure_hpa)::double precision AS local_pressure_hpa,
        AVG(t.sea_level_pressure_hpa)::double precision AS sea_level_pressure_hpa,
        AVG(t.humidity_pct)::double precision AS humidity_pct,
        AVG(t.solar_radiation_mj_m2)::double precision AS solar_radiation_mj_m2,
        AVG(t.sunshine_hr)::double precision AS sunshine_hr
    FROM (
        SELECT DISTINCT ON (a.district_name)
            a.observed_at,
            a.temp_c,
            a.wind_dir_deg,
            a.wind_speed_ms,
            a.precip_mm,
            a.local_pressure_hpa,
            a.sea_level_pressure_hpa,
            a.humidity_pct,
            a.solar_radiation_mj_m2,
            a.sunshine_hr
        FROM std.seoul_aws_district_hourly a
        INNER JOIN meta.seoul_district_grid_map g_self
            ON g_self.district_name = '종로구'
        INNER JOIN meta.seoul_district_grid_map g_n
            ON g_n.district_name = a.district_name
           AND g_n.district_name <> '종로구'
           AND ABS(g_n.nx - g_self.nx) <= 1
           AND ABS(g_n.ny - g_self.ny) <= 1
        WHERE w.district_name = '종로구'
          AND a.observed_at <= w.base_datetime
        ORDER BY a.district_name, a.observed_at DESC
    ) t
) aws_neigh ON TRUE
LEFT JOIN static_features sf
    ON sf.district_name = w.district_name;
