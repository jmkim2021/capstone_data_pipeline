BEGIN;

ALTER TABLE IF EXISTS std.kma_ultra_now_std
    ADD COLUMN IF NOT EXISTS rain_1h_text TEXT,
    ADD COLUMN IF NOT EXISTS rain_1h_parse_type TEXT,
    ADD COLUMN IF NOT EXISTS requested_at TIMESTAMPTZ;

ALTER TABLE IF EXISTS std.kma_ultra_fcst_std
    ADD COLUMN IF NOT EXISTS forecast_precip_parse_type TEXT,
    ADD COLUMN IF NOT EXISTS requested_at TIMESTAMPTZ;

ALTER TABLE IF EXISTS std.kma_short_fcst_std
    ADD COLUMN IF NOT EXISTS forecast_precip_parse_type TEXT,
    ADD COLUMN IF NOT EXISTS requested_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_kma_ultra_now_std_requested_at
    ON std.kma_ultra_now_std (requested_at);

CREATE INDEX IF NOT EXISTS idx_kma_ultra_fcst_std_requested_at
    ON std.kma_ultra_fcst_std (requested_at);

CREATE INDEX IF NOT EXISTS idx_kma_short_fcst_std_requested_at
    ON std.kma_short_fcst_std (requested_at);

COMMIT;
