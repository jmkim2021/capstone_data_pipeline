BEGIN;

-- trainset_base 성능: decision_base AS MATERIALIZED + lag는 model_features 재조인 대신 decision_base self-join +
-- split_bounds는 labeled max만 별도 스캔. mart 강우/하천 latest 인덱스는 sql/028_operational_reliability.sql

CREATE SCHEMA IF NOT EXISTS mart;

-- NOTE: PostgreSQL은 CREATE OR REPLACE VIEW로 기존 뷰 컬럼명을 변경할 수 없습니다.
-- 라벨 기준/컬럼 구성이 바뀌는 경우를 위해, 아래 3개 뷰는 재생성 전에 명시적으로 DROP 합니다.
DROP VIEW IF EXISTS mart.seoul_district_heavyrain_trainset CASCADE;
DROP VIEW IF EXISTS mart.seoul_district_heavyrain_trainset_pending CASCADE;
DROP VIEW IF EXISTS mart.seoul_district_heavyrain_trainset_base CASCADE;
DROP VIEW IF EXISTS mart.seoul_district_realtime_features_latest CASCADE;

-- floating_pop_korean: OA-15439 내국인 생활인구 proxy.
-- 조인 규칙: 각 구에 대해 (base_date+base_hour)를 KST 시각으로 해석한 observed_at이
-- m.base_datetime 이하인 행 중 observed_at이 가장 최근인 1행(as-of, 누수 방지에 유리).
-- mart.seoul_living_population_korean_district_latest(구별 단순 최신 1행)와는 별개.
CREATE OR REPLACE VIEW mart.seoul_district_realtime_features_latest AS
SELECT DISTINCT ON (m.district_name)
    product_type,
    m.district_name,
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
    weather_requested_at,
    rainfall_observed_at,
    rainfall_lag_minutes,
    rainfall_station_count,
    avg_rain_10m_mm,
    max_rain_10m_mm,
    river_observed_at,
    river_lag_minutes,
    river_station_count,
    avg_water_level_m,
    max_water_level_m,
    max_control_level_m,
    hsr_observed_at,
    hsr_lag_minutes,
    hsr_comp_type,
    hsr_data_type_cd,
    hsr_value_numeric,
    hsr_unit,
    hsr_is_no_echo,
    aws_observed_at,
    aws_lag_minutes,
    aws_temp_c,
    aws_wind_dir_deg,
    aws_wind_speed_ms,
    aws_precip_mm,
    aws_local_pressure_hpa,
    aws_sea_level_pressure_hpa,
    aws_humidity_pct,
    aws_solar_radiation_mj_m2,
    aws_sunshine_hr,
    aws_missing_flag,
    aws_neighbor_imputed,
    rain_gauge_current_count,
    flood_trace_count_2023,
    flood_trace_count_2024,
    flood_trace_count_2025,
    flood_trace_count_total,
    flooded_area_sqm_2023,
    flooded_area_sqm_2024,
    flooded_area_sqm_2025,
    flooded_area_sqm_total,
    disaster_risk_zone_count,
    disaster_risk_zone_in_progress_count,
    disaster_risk_zone_expired_count,
    lp.korean_population AS floating_pop_korean,
    lp.base_date AS floating_pop_korean_base_date,
    lp.base_hour AS floating_pop_korean_base_hour,
    lp.observed_at AS floating_pop_korean_observed_at,
    ROUND(
        EXTRACT(EPOCH FROM (m.base_datetime - lp.observed_at)) / 3600.0,
        2
    )::double precision AS floating_pop_korean_lag_hours
FROM mart.seoul_district_model_features m
LEFT JOIN LATERAL (
    SELECT
        lp2.base_date,
        lp2.base_hour,
        lp2.korean_population,
        ((lp2.base_date + (lp2.base_hour * INTERVAL '1 hour')) AT TIME ZONE 'Asia/Seoul') AS observed_at
    FROM ref.seoul_living_population_korean_district_hourly lp2
    WHERE lp2.district_name = m.district_name
      AND ((lp2.base_date + (lp2.base_hour * INTERVAL '1 hour')) AT TIME ZONE 'Asia/Seoul')
          <= m.base_datetime
    ORDER BY observed_at DESC, lp2.updated_at DESC
    LIMIT 1
) lp ON TRUE
WHERE product_type = 'ultra_now'
  AND target_datetime = base_datetime
ORDER BY m.district_name, base_datetime DESC, weather_requested_at DESC;

CREATE OR REPLACE VIEW mart.seoul_district_heavyrain_trainset_base AS
WITH decision_base AS MATERIALIZED (
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
        weather_requested_at,
        rainfall_observed_at,
        rainfall_lag_minutes,
        rainfall_station_count,
        avg_rain_10m_mm,
        max_rain_10m_mm,
        river_observed_at,
        river_lag_minutes,
        river_station_count,
        avg_water_level_m,
        max_water_level_m,
        max_control_level_m,
        hsr_observed_at,
        hsr_lag_minutes,
        hsr_comp_type,
        hsr_data_type_cd,
        hsr_value_numeric,
        hsr_unit,
        hsr_is_no_echo,
        aws_observed_at,
        aws_lag_minutes,
        aws_temp_c,
        aws_wind_dir_deg,
        aws_wind_speed_ms,
        aws_precip_mm,
        aws_local_pressure_hpa,
        aws_sea_level_pressure_hpa,
        aws_humidity_pct,
        aws_solar_radiation_mj_m2,
        aws_sunshine_hr,
        aws_missing_flag,
        aws_neighbor_imputed,
        rain_gauge_current_count,
        flood_trace_count_2023,
        flood_trace_count_2024,
        flood_trace_count_2025,
        flood_trace_count_total,
        flooded_area_sqm_2023,
        flooded_area_sqm_2024,
        flooded_area_sqm_2025,
        flooded_area_sqm_total,
        disaster_risk_zone_count,
        disaster_risk_zone_in_progress_count,
        disaster_risk_zone_expired_count
    FROM mart.seoul_district_model_features
    WHERE product_type = 'ultra_now'
      AND target_datetime = base_datetime
),
lag_enriched AS (
    SELECT
        b.*,
        l1.precip_mm AS lag_precip_1h_mm,
        l2.precip_mm AS lag_precip_2h_mm,
        l3.temp_c AS lag_temp_3h_c,
        l3.humidity_pct AS lag_humidity_3h_pct
    FROM decision_base b
    LEFT JOIN decision_base l1
        ON l1.product_type = b.product_type
       AND l1.district_name = b.district_name
       AND l1.target_datetime = l1.base_datetime
       AND l1.base_datetime = b.base_datetime - INTERVAL '1 hour'
    LEFT JOIN decision_base l2
        ON l2.product_type = b.product_type
       AND l2.district_name = b.district_name
       AND l2.target_datetime = l2.base_datetime
       AND l2.base_datetime = b.base_datetime - INTERVAL '2 hours'
    LEFT JOIN decision_base l3
        ON l3.product_type = b.product_type
       AND l3.district_name = b.district_name
       AND l3.target_datetime = l3.base_datetime
       AND l3.base_datetime = b.base_datetime - INTERVAL '3 hours'
),
label_enriched AS (
    SELECT
        b.*,
        b.base_datetime + INTERVAL '3 hours' AS label_window_end,
        b.base_datetime + INTERVAL '3 hours 20 minutes' AS label_ready_at,
        label_data.label_source_point_count,
        label_data.target_rain_1h_mm,
        label_data.target_rain_3h_mm,
        CASE
            WHEN label_data.target_rain_3h_mm IS NULL THEN NULL
            WHEN label_data.target_rain_1h_mm >= 30.0
              OR label_data.target_rain_3h_mm >= 60.0
            THEN 1
            ELSE 0
        END AS target_heavy_rain_flag
    FROM lag_enriched b
    LEFT JOIN LATERAL (
        SELECT
            COUNT(r.observed_at) AS label_source_point_count,
            CASE
                WHEN COUNT(r.observed_at) FILTER (
                    WHERE r.observed_at <= b.base_datetime + INTERVAL '1 hour'
                ) = 0 THEN NULL
                ELSE ROUND(
                    SUM(COALESCE(r.max_rain_10m_mm, 0.0)) FILTER (
                        WHERE r.observed_at <= b.base_datetime + INTERVAL '1 hour'
                    )::numeric,
                    3
                )::DOUBLE PRECISION
            END AS target_rain_1h_mm,
            CASE
                WHEN COUNT(r.observed_at) = 0 THEN NULL
                ELSE ROUND(SUM(COALESCE(r.max_rain_10m_mm, 0.0))::numeric, 3)::DOUBLE PRECISION
            END AS target_rain_3h_mm
        FROM mart.seoul_rainfall_district_latest r
        WHERE r.district_name = b.district_name
          AND r.observed_at > b.base_datetime
          AND r.observed_at <= b.base_datetime + INTERVAL '3 hours'
    ) label_data ON TRUE
),
label_rule_enriched AS (
    SELECT
        e.*,
        CASE
            WHEN e.target_rain_3h_mm IS NULL THEN NULL
            WHEN COALESCE((e.target_rain_1h_mm >= 20.0), FALSE)
              OR COALESCE((LEAD(e.target_rain_1h_mm, 1) OVER w >= 20.0), FALSE)
              OR COALESCE((LEAD(e.target_rain_1h_mm, 2) OVER w >= 20.0), FALSE)
              OR COALESCE((LEAD(e.target_rain_1h_mm, 3) OVER w >= 20.0), FALSE)
              OR COALESCE((e.target_rain_3h_mm >= 40.0), FALSE)
              OR COALESCE((LEAD(e.target_rain_3h_mm, 1) OVER w >= 40.0), FALSE)
              OR COALESCE((LEAD(e.target_rain_3h_mm, 2) OVER w >= 40.0), FALSE)
              OR COALESCE((LEAD(e.target_rain_3h_mm, 3) OVER w >= 40.0), FALSE)
            THEN 1
            ELSE 0
        END AS label_rule_flag
    FROM label_enriched e
    WINDOW w AS (PARTITION BY e.district_name ORDER BY e.base_datetime)
),
split_bounds AS (
    SELECT MAX(m.base_datetime) AS latest_labeled_base
    FROM mart.seoul_district_model_features m
    WHERE m.product_type = 'ultra_now'
      AND m.target_datetime = m.base_datetime
      AND CURRENT_TIMESTAMP >= m.base_datetime + INTERVAL '3 hours 20 minutes'
)
SELECT
    e.product_type,
    e.district_name,
    e.base_datetime,
    e.target_datetime,
    e.lead_minutes,
    e.precip_mm,
    e.temp_c,
    e.humidity_pct,
    e.pop_pct,
    e.wind_speed_ms,
    e.sky_code,
    e.precip_type_code,
    e.weather_requested_at,
    e.rainfall_observed_at,
    e.rainfall_lag_minutes,
    e.rainfall_station_count,
    e.avg_rain_10m_mm,
    e.max_rain_10m_mm,
    e.river_observed_at,
    e.river_lag_minutes,
    e.river_station_count,
    e.avg_water_level_m,
    e.max_water_level_m,
    e.max_control_level_m,
    e.hsr_observed_at,
    e.hsr_lag_minutes,
    e.hsr_comp_type,
    e.hsr_data_type_cd,
    e.hsr_value_numeric,
    e.hsr_unit,
    e.hsr_is_no_echo,
    e.aws_observed_at,
    e.aws_lag_minutes,
    e.aws_temp_c,
    e.aws_wind_dir_deg,
    e.aws_wind_speed_ms,
    e.aws_precip_mm,
    e.aws_local_pressure_hpa,
    e.aws_sea_level_pressure_hpa,
    e.aws_humidity_pct,
    e.aws_solar_radiation_mj_m2,
    e.aws_sunshine_hr,
    e.aws_missing_flag,
    e.aws_neighbor_imputed,
    e.rain_gauge_current_count,
    e.flood_trace_count_2023,
    e.flood_trace_count_2024,
    e.flood_trace_count_2025,
    e.flood_trace_count_total,
    e.flooded_area_sqm_2023,
    e.flooded_area_sqm_2024,
    e.flooded_area_sqm_2025,
    e.flooded_area_sqm_total,
    e.disaster_risk_zone_count,
    e.disaster_risk_zone_in_progress_count,
    e.disaster_risk_zone_expired_count,
    CASE
        WHEN e.humidity_pct IS NULL OR e.humidity_pct <= 0 OR e.temp_c IS NULL THEN NULL
        ELSE ROUND(
            ((
                237.7 * (
                    LN(e.humidity_pct / 100.0) + (17.27 * e.temp_c) / (237.7 + e.temp_c)
                )
            ) / (
                17.27 - (
                    LN(e.humidity_pct / 100.0) + (17.27 * e.temp_c) / (237.7 + e.temp_c)
                )
            ))::numeric,
            3
        )::DOUBLE PRECISION
    END AS dew_point_c,
    CASE
        WHEN e.precip_mm IS NULL OR e.lag_precip_1h_mm IS NULL OR e.lag_precip_2h_mm IS NULL THEN NULL
        ELSE ROUND(
            (COALESCE(e.precip_mm, 0.0) + COALESCE(e.lag_precip_1h_mm, 0.0) + COALESCE(e.lag_precip_2h_mm, 0.0))::numeric,
            3
        )::DOUBLE PRECISION
    END AS past_rain_3h_mm,
    CASE
        WHEN e.temp_c IS NULL OR e.lag_temp_3h_c IS NULL THEN NULL
        ELSE ROUND((e.temp_c - e.lag_temp_3h_c)::numeric, 3)::DOUBLE PRECISION
    END AS temp_change_3h_c,
    CASE
        WHEN e.humidity_pct IS NULL OR e.lag_humidity_3h_pct IS NULL THEN NULL
        ELSE ROUND((e.humidity_pct - e.lag_humidity_3h_pct)::numeric, 3)::DOUBLE PRECISION
    END AS humidity_change_3h_pct,
    CASE
        WHEN e.temp_c IS NULL OR e.humidity_pct IS NULL THEN NULL
        ELSE ROUND(((e.temp_c * e.humidity_pct) / 100.0)::numeric, 3)::DOUBLE PRECISION
    END AS moist_energy,
    e.label_window_end,
    e.label_ready_at,
    e.label_source_point_count,
    CASE
        WHEN CURRENT_TIMESTAMP < e.label_ready_at THEN NULL
        ELSE e.label_rule_flag
    END AS target_heavy_rain_flag,
    CASE
        WHEN CURRENT_TIMESTAMP < e.label_ready_at THEN NULL
        ELSE e.label_rule_flag
    END AS label,
    CASE
        WHEN CURRENT_TIMESTAMP < e.label_ready_at THEN NULL
        ELSE e.target_rain_1h_mm
    END AS target_rain_1h_mm,
    CASE
        WHEN CURRENT_TIMESTAMP < e.label_ready_at THEN NULL
        ELSE e.target_rain_3h_mm
    END AS target_rain_3h_mm,
    CASE
        WHEN CURRENT_TIMESTAMP < e.label_ready_at THEN 'pending'
        ELSE 'labeled'
    END AS dataset_status,
    CASE
        WHEN CURRENT_TIMESTAMP < e.label_ready_at THEN FALSE
        WHEN e.target_rain_3h_mm IS NULL THEN FALSE
        ELSE TRUE
    END AS is_trainable,
    CASE
        WHEN CURRENT_TIMESTAMP < e.label_ready_at THEN 'pending'
        WHEN s.latest_labeled_base IS NULL THEN 'pending'
        WHEN e.base_datetime < s.latest_labeled_base - INTERVAL '24 hours' THEN 'train'
        WHEN e.base_datetime < s.latest_labeled_base - INTERVAL '12 hours' THEN 'valid'
        ELSE 'test'
    END AS split_type,
    'seoul_district_heavyrain_v2'::TEXT AS data_version
FROM label_rule_enriched e
CROSS JOIN split_bounds s;

CREATE OR REPLACE VIEW mart.seoul_district_heavyrain_trainset_pending AS
SELECT DISTINCT ON (district_name)
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
    weather_requested_at,
    rainfall_observed_at,
    rainfall_lag_minutes,
    rainfall_station_count,
    avg_rain_10m_mm,
    max_rain_10m_mm,
    river_observed_at,
    river_lag_minutes,
    river_station_count,
    avg_water_level_m,
    max_water_level_m,
    max_control_level_m,
    hsr_observed_at,
    hsr_lag_minutes,
    hsr_comp_type,
    hsr_data_type_cd,
    hsr_value_numeric,
    hsr_unit,
    hsr_is_no_echo,
    aws_observed_at,
    aws_lag_minutes,
    aws_temp_c,
    aws_wind_dir_deg,
    aws_wind_speed_ms,
    aws_precip_mm,
    aws_local_pressure_hpa,
    aws_sea_level_pressure_hpa,
    aws_humidity_pct,
    aws_solar_radiation_mj_m2,
    aws_sunshine_hr,
    aws_missing_flag,
    aws_neighbor_imputed,
    rain_gauge_current_count,
    flood_trace_count_2023,
    flood_trace_count_2024,
    flood_trace_count_2025,
    flood_trace_count_total,
    flooded_area_sqm_2023,
    flooded_area_sqm_2024,
    flooded_area_sqm_2025,
    flooded_area_sqm_total,
    disaster_risk_zone_count,
    disaster_risk_zone_in_progress_count,
    disaster_risk_zone_expired_count,
    dew_point_c,
    past_rain_3h_mm,
    temp_change_3h_c,
    humidity_change_3h_pct,
    moist_energy,
    label_window_end,
    label_ready_at,
    label_source_point_count,
    target_heavy_rain_flag,
    label,
    target_rain_1h_mm,
    target_rain_3h_mm,
    dataset_status,
    is_trainable,
    split_type,
    data_version
FROM mart.seoul_district_heavyrain_trainset_base
WHERE dataset_status = 'pending'
ORDER BY district_name, base_datetime DESC, weather_requested_at DESC;

CREATE OR REPLACE VIEW mart.seoul_district_heavyrain_trainset AS
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
    weather_requested_at,
    rainfall_observed_at,
    rainfall_lag_minutes,
    rainfall_station_count,
    avg_rain_10m_mm,
    max_rain_10m_mm,
    river_observed_at,
    river_lag_minutes,
    river_station_count,
    avg_water_level_m,
    max_water_level_m,
    max_control_level_m,
    hsr_observed_at,
    hsr_lag_minutes,
    hsr_comp_type,
    hsr_data_type_cd,
    hsr_value_numeric,
    hsr_unit,
    hsr_is_no_echo,
    aws_observed_at,
    aws_lag_minutes,
    aws_temp_c,
    aws_wind_dir_deg,
    aws_wind_speed_ms,
    aws_precip_mm,
    aws_local_pressure_hpa,
    aws_sea_level_pressure_hpa,
    aws_humidity_pct,
    aws_solar_radiation_mj_m2,
    aws_sunshine_hr,
    aws_missing_flag,
    aws_neighbor_imputed,
    rain_gauge_current_count,
    flood_trace_count_2023,
    flood_trace_count_2024,
    flood_trace_count_2025,
    flood_trace_count_total,
    flooded_area_sqm_2023,
    flooded_area_sqm_2024,
    flooded_area_sqm_2025,
    flooded_area_sqm_total,
    disaster_risk_zone_count,
    disaster_risk_zone_in_progress_count,
    disaster_risk_zone_expired_count,
    dew_point_c,
    past_rain_3h_mm,
    temp_change_3h_c,
    humidity_change_3h_pct,
    moist_energy,
    label_window_end,
    label_ready_at,
    label_source_point_count,
    target_heavy_rain_flag,
    label,
    target_rain_1h_mm,
    target_rain_3h_mm,
    dataset_status,
    is_trainable,
    split_type,
    data_version
FROM mart.seoul_district_heavyrain_trainset_base
WHERE dataset_status = 'labeled';

COMMIT;
