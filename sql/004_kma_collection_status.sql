BEGIN;

CREATE SCHEMA IF NOT EXISTS mart;

CREATE OR REPLACE VIEW mart.kma_collection_status AS
SELECT
    'ultra_now'::TEXT AS product_type,
    'raw'::TEXT AS data_layer,
    COUNT(*)::BIGINT AS row_count,
    MAX(requested_at) AS latest_requested_at,
    MAX((base_date || base_time)::TEXT) AS latest_base_key
FROM raw.kma_ultra_now_raw

UNION ALL

SELECT
    'ultra_now'::TEXT AS product_type,
    'std'::TEXT AS data_layer,
    COUNT(*)::BIGINT AS row_count,
    MAX(requested_at) AS latest_requested_at,
    TO_CHAR(MAX(base_datetime), 'YYYYMMDDHH24MI') AS latest_base_key
FROM std.kma_ultra_now_std

UNION ALL

SELECT
    'ultra_now_district'::TEXT AS product_type,
    'mart'::TEXT AS data_layer,
    COUNT(*)::BIGINT AS row_count,
    MAX(requested_at) AS latest_requested_at,
    TO_CHAR(MAX(base_datetime), 'YYYYMMDDHH24MI') AS latest_base_key
FROM mart.seoul_district_ultra_now

UNION ALL

SELECT
    'ultra_fcst'::TEXT AS product_type,
    'raw'::TEXT AS data_layer,
    COUNT(*)::BIGINT AS row_count,
    MAX(requested_at) AS latest_requested_at,
    MAX((base_date || base_time)::TEXT) AS latest_base_key
FROM raw.kma_ultra_fcst_raw

UNION ALL

SELECT
    'ultra_fcst'::TEXT AS product_type,
    'std'::TEXT AS data_layer,
    COUNT(*)::BIGINT AS row_count,
    MAX(requested_at) AS latest_requested_at,
    TO_CHAR(MAX(base_datetime), 'YYYYMMDDHH24MI') AS latest_base_key
FROM std.kma_ultra_fcst_std

UNION ALL

SELECT
    'ultra_fcst_district'::TEXT AS product_type,
    'mart'::TEXT AS data_layer,
    COUNT(*)::BIGINT AS row_count,
    MAX(requested_at) AS latest_requested_at,
    TO_CHAR(MAX(base_datetime), 'YYYYMMDDHH24MI') AS latest_base_key
FROM mart.seoul_district_ultra_fcst

UNION ALL

SELECT
    'short_fcst'::TEXT AS product_type,
    'raw'::TEXT AS data_layer,
    COUNT(*)::BIGINT AS row_count,
    MAX(requested_at) AS latest_requested_at,
    MAX((base_date || base_time)::TEXT) AS latest_base_key
FROM raw.kma_short_fcst_raw

UNION ALL

SELECT
    'short_fcst'::TEXT AS product_type,
    'std'::TEXT AS data_layer,
    COUNT(*)::BIGINT AS row_count,
    MAX(requested_at) AS latest_requested_at,
    TO_CHAR(MAX(base_datetime), 'YYYYMMDDHH24MI') AS latest_base_key
FROM std.kma_short_fcst_std

UNION ALL

SELECT
    'short_fcst_district'::TEXT AS product_type,
    'mart'::TEXT AS data_layer,
    COUNT(*)::BIGINT AS row_count,
    MAX(requested_at) AS latest_requested_at,
    TO_CHAR(MAX(base_datetime), 'YYYYMMDDHH24MI') AS latest_base_key
FROM mart.seoul_district_short_fcst
;

COMMIT;
