BEGIN;

CREATE SCHEMA IF NOT EXISTS meta;

CREATE TABLE IF NOT EXISTS meta.seoul_district_grid_map (
    district_name TEXT NOT NULL,
    nx INTEGER NOT NULL,
    ny INTEGER NOT NULL,
    weight NUMERIC(10, 6) NOT NULL DEFAULT 1.0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    source TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (district_name, nx, ny)
);

CREATE INDEX IF NOT EXISTS idx_seoul_district_grid_map_grid
    ON meta.seoul_district_grid_map (nx, ny);

COMMIT;
