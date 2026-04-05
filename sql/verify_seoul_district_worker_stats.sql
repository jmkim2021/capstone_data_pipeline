SELECT
    base_year,
    COUNT(*) AS row_count,
    COUNT(DISTINCT district_name) AS district_name_distinct_count,
    COUNT(*) FILTER (WHERE total_worker_count IS NULL) AS null_total_worker_count_rows,
    COUNT(*) FILTER (WHERE total_worker_count < 0) AS negative_total_worker_count_rows
FROM ref.seoul_district_worker_stats
WHERE base_year = 2024
GROUP BY base_year;

DO $$
DECLARE
    v_row_count INT;
    v_district_count INT;
    v_null_count INT;
    v_negative_count INT;
BEGIN
    SELECT
        COUNT(*),
        COUNT(DISTINCT district_name),
        COUNT(*) FILTER (WHERE total_worker_count IS NULL),
        COUNT(*) FILTER (WHERE total_worker_count < 0)
    INTO
        v_row_count,
        v_district_count,
        v_null_count,
        v_negative_count
    FROM ref.seoul_district_worker_stats
    WHERE base_year = 2024;

    IF v_row_count <> 25 THEN
        RAISE EXCEPTION 'Expected 25 rows for base_year=2024, got %', v_row_count;
    END IF;

    IF v_district_count <> 25 THEN
        RAISE EXCEPTION 'Expected 25 distinct districts for base_year=2024, got %', v_district_count;
    END IF;

    IF v_null_count <> 0 THEN
        RAISE EXCEPTION 'Found % NULL total_worker_count rows for base_year=2024', v_null_count;
    END IF;

    IF v_negative_count <> 0 THEN
        RAISE EXCEPTION 'Found % negative total_worker_count rows for base_year=2024', v_negative_count;
    END IF;
END
$$;

SELECT
    base_year,
    district_name,
    total_worker_count,
    source_file_name,
    loaded_at
FROM ref.seoul_district_worker_stats
WHERE base_year = 2024
ORDER BY district_name;
