CREATE OR REPLACE VIEW mart.seoul_district_flood_features AS
WITH districts AS (
    SELECT DISTINCT district_name
    FROM meta.seoul_district_grid_map
),
rain_gauge AS (
    SELECT
        substring(station_address from '서울특별시 ([^ ]+)') AS district_name,
        COUNT(*) AS rain_gauge_current_count
    FROM ref.seoul_rain_gauge_station_current
    GROUP BY 1
),
flood_trace AS (
    SELECT
        district_name,
        COUNT(*) FILTER (WHERE source_year = 2023) AS flood_trace_count_2023,
        COUNT(*) FILTER (WHERE source_year = 2024) AS flood_trace_count_2024,
        COUNT(*) FILTER (WHERE source_year = 2025) AS flood_trace_count_2025,
        ROUND(SUM(flooded_area_sqm) FILTER (WHERE source_year = 2023)::numeric, 2) AS flooded_area_sqm_2023,
        ROUND(SUM(flooded_area_sqm) FILTER (WHERE source_year = 2024)::numeric, 2) AS flooded_area_sqm_2024,
        ROUND(SUM(flooded_area_sqm) FILTER (WHERE source_year = 2025)::numeric, 2) AS flooded_area_sqm_2025
    FROM ref.seoul_flood_trace
    GROUP BY district_name
),
risk_zone AS (
    SELECT
        district_name,
        COUNT(*) AS disaster_risk_zone_count,
        COUNT(*) FILTER (WHERE progress_status = '추진중') AS disaster_risk_zone_in_progress_count,
        COUNT(*) FILTER (WHERE progress_status = '고시실효') AS disaster_risk_zone_expired_count
    FROM ref.seoul_disaster_risk_zone
    GROUP BY district_name
)
SELECT
    d.district_name,
    COALESCE(rg.rain_gauge_current_count, 0) AS rain_gauge_current_count,
    COALESCE(ft.flood_trace_count_2023, 0) AS flood_trace_count_2023,
    COALESCE(ft.flood_trace_count_2024, 0) AS flood_trace_count_2024,
    COALESCE(ft.flood_trace_count_2025, 0) AS flood_trace_count_2025,
    COALESCE(ft.flooded_area_sqm_2023, 0) AS flooded_area_sqm_2023,
    COALESCE(ft.flooded_area_sqm_2024, 0) AS flooded_area_sqm_2024,
    COALESCE(ft.flooded_area_sqm_2025, 0) AS flooded_area_sqm_2025,
    COALESCE(rz.disaster_risk_zone_count, 0) AS disaster_risk_zone_count,
    COALESCE(rz.disaster_risk_zone_in_progress_count, 0) AS disaster_risk_zone_in_progress_count,
    COALESCE(rz.disaster_risk_zone_expired_count, 0) AS disaster_risk_zone_expired_count
FROM districts d
LEFT JOIN rain_gauge rg ON rg.district_name = d.district_name
LEFT JOIN flood_trace ft ON ft.district_name = d.district_name
LEFT JOIN risk_zone rz ON rz.district_name = d.district_name
ORDER BY d.district_name;
