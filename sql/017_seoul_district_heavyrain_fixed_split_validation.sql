WITH split_counts AS (
    SELECT 'train' AS split_name, COUNT(*) AS row_count
    FROM mart.seoul_district_heavyrain_train_fixed_v2_20260401
    UNION ALL
    SELECT 'valid' AS split_name, COUNT(*) AS row_count
    FROM mart.seoul_district_heavyrain_valid_fixed_v2_20260401
    UNION ALL
    SELECT 'test' AS split_name, COUNT(*) AS row_count
    FROM mart.seoul_district_heavyrain_test_fixed_v2_20260401
)
SELECT *
FROM split_counts
ORDER BY split_name;

WITH column_meta AS (
    SELECT
        table_name,
        ordinal_position,
        column_name,
        udt_name
    FROM information_schema.columns
    WHERE table_schema = 'mart'
      AND table_name IN (
          'seoul_district_heavyrain_train_fixed_v2_20260401',
          'seoul_district_heavyrain_valid_fixed_v2_20260401',
          'seoul_district_heavyrain_test_fixed_v2_20260401'
      )
),
signatures AS (
    SELECT
        table_name,
        STRING_AGG(column_name, ',' ORDER BY ordinal_position) AS column_order_signature,
        STRING_AGG(column_name || ':' || udt_name, ',' ORDER BY ordinal_position) AS column_type_signature
    FROM column_meta
    GROUP BY table_name
)
SELECT
    COUNT(DISTINCT column_order_signature) = 1 AS same_column_names_and_order,
    COUNT(DISTINCT column_type_signature) = 1 AS same_column_names_order_and_types
FROM signatures;

SELECT
    table_name,
    ordinal_position,
    column_name,
    udt_name
FROM information_schema.columns
WHERE table_schema = 'mart'
  AND table_name IN (
      'seoul_district_heavyrain_train_fixed_v2_20260401',
      'seoul_district_heavyrain_valid_fixed_v2_20260401',
      'seoul_district_heavyrain_test_fixed_v2_20260401'
  )
ORDER BY table_name, ordinal_position;

SELECT
    'train' AS split_name,
    COUNT(*) FILTER (WHERE dew_point_c IS NULL) AS dew_point_c_null_count,
    COUNT(*) FILTER (WHERE dew_point_c IS NOT NULL) AS dew_point_c_not_null_count,
    COUNT(*) FILTER (WHERE past_rain_3h_mm IS NULL) AS past_rain_3h_mm_null_count,
    COUNT(*) FILTER (WHERE past_rain_3h_mm IS NOT NULL) AS past_rain_3h_mm_not_null_count,
    COUNT(*) FILTER (WHERE temp_change_3h_c IS NULL) AS temp_change_3h_c_null_count,
    COUNT(*) FILTER (WHERE temp_change_3h_c IS NOT NULL) AS temp_change_3h_c_not_null_count,
    COUNT(*) FILTER (WHERE humidity_change_3h_pct IS NULL) AS humidity_change_3h_pct_null_count,
    COUNT(*) FILTER (WHERE humidity_change_3h_pct IS NOT NULL) AS humidity_change_3h_pct_not_null_count,
    COUNT(*) FILTER (WHERE moist_energy IS NULL) AS moist_energy_null_count,
    COUNT(*) FILTER (WHERE moist_energy IS NOT NULL) AS moist_energy_not_null_count,
    COUNT(*) FILTER (WHERE label IS NULL) AS label_null_count,
    COUNT(*) FILTER (WHERE label IS NOT NULL) AS label_not_null_count
FROM mart.seoul_district_heavyrain_train_fixed_v2_20260401
UNION ALL
SELECT
    'valid' AS split_name,
    COUNT(*) FILTER (WHERE dew_point_c IS NULL) AS dew_point_c_null_count,
    COUNT(*) FILTER (WHERE dew_point_c IS NOT NULL) AS dew_point_c_not_null_count,
    COUNT(*) FILTER (WHERE past_rain_3h_mm IS NULL) AS past_rain_3h_mm_null_count,
    COUNT(*) FILTER (WHERE past_rain_3h_mm IS NOT NULL) AS past_rain_3h_mm_not_null_count,
    COUNT(*) FILTER (WHERE temp_change_3h_c IS NULL) AS temp_change_3h_c_null_count,
    COUNT(*) FILTER (WHERE temp_change_3h_c IS NOT NULL) AS temp_change_3h_c_not_null_count,
    COUNT(*) FILTER (WHERE humidity_change_3h_pct IS NULL) AS humidity_change_3h_pct_null_count,
    COUNT(*) FILTER (WHERE humidity_change_3h_pct IS NOT NULL) AS humidity_change_3h_pct_not_null_count,
    COUNT(*) FILTER (WHERE moist_energy IS NULL) AS moist_energy_null_count,
    COUNT(*) FILTER (WHERE moist_energy IS NOT NULL) AS moist_energy_not_null_count,
    COUNT(*) FILTER (WHERE label IS NULL) AS label_null_count,
    COUNT(*) FILTER (WHERE label IS NOT NULL) AS label_not_null_count
FROM mart.seoul_district_heavyrain_valid_fixed_v2_20260401
UNION ALL
SELECT
    'test' AS split_name,
    COUNT(*) FILTER (WHERE dew_point_c IS NULL) AS dew_point_c_null_count,
    COUNT(*) FILTER (WHERE dew_point_c IS NOT NULL) AS dew_point_c_not_null_count,
    COUNT(*) FILTER (WHERE past_rain_3h_mm IS NULL) AS past_rain_3h_mm_null_count,
    COUNT(*) FILTER (WHERE past_rain_3h_mm IS NOT NULL) AS past_rain_3h_mm_not_null_count,
    COUNT(*) FILTER (WHERE temp_change_3h_c IS NULL) AS temp_change_3h_c_null_count,
    COUNT(*) FILTER (WHERE temp_change_3h_c IS NOT NULL) AS temp_change_3h_c_not_null_count,
    COUNT(*) FILTER (WHERE humidity_change_3h_pct IS NULL) AS humidity_change_3h_pct_null_count,
    COUNT(*) FILTER (WHERE humidity_change_3h_pct IS NOT NULL) AS humidity_change_3h_pct_not_null_count,
    COUNT(*) FILTER (WHERE moist_energy IS NULL) AS moist_energy_null_count,
    COUNT(*) FILTER (WHERE moist_energy IS NOT NULL) AS moist_energy_not_null_count,
    COUNT(*) FILTER (WHERE label IS NULL) AS label_null_count,
    COUNT(*) FILTER (WHERE label IS NOT NULL) AS label_not_null_count
FROM mart.seoul_district_heavyrain_test_fixed_v2_20260401
ORDER BY split_name;

SELECT
    base_datetime,
    district_name,
    temp_c,
    humidity_pct,
    dew_point_c
FROM mart.seoul_district_heavyrain_snapshot_fixed_v2_20260401
WHERE dew_point_c IS NOT NULL
ORDER BY base_datetime, district_name
LIMIT 5;

SELECT
    base_datetime,
    district_name,
    precip_mm,
    past_rain_3h_mm
FROM mart.seoul_district_heavyrain_snapshot_fixed_v2_20260401
WHERE past_rain_3h_mm IS NOT NULL
ORDER BY base_datetime, district_name
LIMIT 5;

SELECT
    base_datetime,
    district_name,
    temp_c,
    temp_change_3h_c
FROM mart.seoul_district_heavyrain_snapshot_fixed_v2_20260401
WHERE temp_change_3h_c IS NOT NULL
ORDER BY base_datetime, district_name
LIMIT 5;

SELECT
    base_datetime,
    district_name,
    humidity_pct,
    humidity_change_3h_pct
FROM mart.seoul_district_heavyrain_snapshot_fixed_v2_20260401
WHERE humidity_change_3h_pct IS NOT NULL
ORDER BY base_datetime, district_name
LIMIT 5;

SELECT
    base_datetime,
    district_name,
    temp_c,
    humidity_pct,
    moist_energy
FROM mart.seoul_district_heavyrain_snapshot_fixed_v2_20260401
WHERE moist_energy IS NOT NULL
ORDER BY base_datetime, district_name
LIMIT 5;

SELECT
    base_datetime,
    district_name,
    label
FROM mart.seoul_district_heavyrain_snapshot_fixed_v2_20260401
WHERE label IS NOT NULL
ORDER BY base_datetime, district_name
LIMIT 5;

SELECT
    split_type,
    label,
    COUNT(*) AS row_count
FROM mart.seoul_district_heavyrain_snapshot_fixed_v2_20260401
GROUP BY split_type, label
ORDER BY split_type, label;
