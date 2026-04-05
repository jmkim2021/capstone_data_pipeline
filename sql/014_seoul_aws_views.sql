CREATE OR REPLACE VIEW mart.seoul_aws_district_timeline AS
SELECT
    district_name,
    station_code,
    observed_at,
    temp_c,
    wind_dir_deg,
    wind_speed_ms,
    precip_mm,
    local_pressure_hpa,
    sea_level_pressure_hpa,
    humidity_pct,
    solar_radiation_mj_m2,
    sunshine_hr,
    source_zip_name,
    source_csv_name,
    loaded_at
FROM std.seoul_aws_district_hourly;

CREATE OR REPLACE VIEW mart.seoul_aws_district_coverage AS
SELECT
    district_name,
    COUNT(*) AS row_count,
    MIN(observed_at) AS min_observed_at,
    MAX(observed_at) AS max_observed_at,
    COUNT(*) FILTER (WHERE precip_mm IS NULL) AS precip_null_count,
    COUNT(*) FILTER (WHERE temp_c IS NULL) AS temp_null_count,
    COUNT(*) FILTER (WHERE humidity_pct IS NULL) AS humidity_null_count
FROM std.seoul_aws_district_hourly
GROUP BY district_name
ORDER BY district_name;
