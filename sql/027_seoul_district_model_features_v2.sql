-- ---------------------------------------------------------------------------
-- mart.seoul_district_model_features v2
-- ---------------------------------------------------------------------------
-- 변경 내용: static_features CTE에 취약계층 밀집도 feature 추가
-- 추가(운영 해석, SELECT 맨 끝 컬럼): river_district_has_stations, river_observation_present,
--   aws_operational_stale_flag (aws_lag_minutes > 1440 분(24h)일 때 true, AWS 없으면 NULL)
--   조인 대상: mart.seoul_vulnerable_population_district_latest (static, district-level)
--   참고: 이 데이터는 slow-changing이므로 realtime as-of 조인이 아닌
--         단순 LEFT JOIN(district_name key)으로 처리.
--
-- 중요: composite vulnerability_score는 이 파일에 포함하지 않음.
--   feature 컬럼만 노출하고, score 합성은 별도 규칙이 확정될 때 추가한다.
--   TODO: vulnerability_score = f(elderly_ratio, disabled_ratio, basic_livelihood_ratio,
--                                 aged_basement_ratio, ...) — 가중치 미정
-- ---------------------------------------------------------------------------
-- 주의: DROP ... CASCADE 는 `mart.seoul_district_model_features`에 의존하는
--   `mart.seoul_district_realtime_features_latest`, `mart.seoul_district_heavyrain_trainset_base`
--   등을 연쇄 삭제한다(016 등에서 재실행 전까지 복구 불가).
-- 기존 컬럼·순서·타입을 유지한 채 끝에 컬럼만 추가하므로 CREATE OR REPLACE 로 갱신한다.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW mart.seoul_district_model_features AS
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
),
vulnerable_features AS (
    SELECT
        district_name,
        elderly_population_total,
        elderly_population_ratio,
        disabled_population_total,
        disabled_population_ratio,
        basic_livelihood_recipient_total,
        basic_livelihood_recipient_ratio,
        basement_household_count,
        aged_basement_household_count,
        aged_basement_household_ratio
    FROM mart.seoul_vulnerable_population_district_latest
),
river_std_districts AS (
    SELECT DISTINCT district_name
    FROM std.seoul_river_stage_std
    WHERE district_name IS NOT NULL
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
    sf.disaster_risk_zone_expired_count,

    -- 취약계층 밀집도 feature (static, district-level)
    -- 소스: ref.seoul_vulnerable_population_district_snapshot
    -- 비율 단위: 0.0~1.0 소수
    vf.elderly_population_total,
    vf.elderly_population_ratio,
    vf.disabled_population_total,
    vf.disabled_population_ratio,
    vf.basic_livelihood_recipient_total,
    vf.basic_livelihood_recipient_ratio,
    vf.basement_household_count,
    vf.aged_basement_household_count,
    vf.aged_basement_household_ratio,

    -- 운영 해석용: 기존 컬럼 순서 유지를 위해 반드시 맨 끝에만 추가 (CREATE OR REPLACE 제약)
    (rstd.district_name IS NOT NULL) AS river_district_has_stations,
    (rv.observed_minute IS NOT NULL) AS river_observation_present,
    CASE
        WHEN COALESCE(aws_own.observed_at, aws_neigh.observed_at) IS NULL THEN NULL
        WHEN EXTRACT(EPOCH FROM (w.base_datetime - COALESCE(aws_own.observed_at, aws_neigh.observed_at))) / 60.0 > 1440
        THEN TRUE
        ELSE FALSE
    END AS aws_operational_stale_flag
    -- TODO: vulnerability_score = weighted_sum(elderly_ratio, disabled_ratio,
    --         basic_livelihood_ratio, aged_basement_ratio)
    --       가중치 확정 후 이 뷰에 추가할 것.

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
LEFT JOIN river_std_districts rstd
    ON rstd.district_name = w.district_name
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
    ON sf.district_name = w.district_name
LEFT JOIN vulnerable_features vf
    ON vf.district_name = w.district_name;
