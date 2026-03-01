-- Sleep data storage (encrypted at rest)
CREATE TABLE IF NOT EXISTS sleep_days (
  id         TEXT PRIMARY KEY,        -- <installId>:<date>
  install_id TEXT NOT NULL,
  day_date   TEXT NOT NULL,           -- YYYY-MM-DD
  data_enc   TEXT NOT NULL,           -- AES-256-GCM encrypted JSON blob (base64)
  iv         TEXT NOT NULL,           -- nonce (base64)
  tag        TEXT NOT NULL,           -- auth tag (base64)
  synced_at  TEXT NOT NULL,           -- ISO 8601
  UNIQUE(install_id, day_date)
);

CREATE INDEX IF NOT EXISTS idx_sleep_days_install
  ON sleep_days(install_id, day_date);

-- Behavior events (encrypted at rest)
CREATE TABLE IF NOT EXISTS behavior_events (
  id         TEXT PRIMARY KEY,        -- <installId>:<date>:<eventName>:<index>
  install_id TEXT NOT NULL,
  day_date   TEXT NOT NULL,
  data_enc   TEXT NOT NULL,
  iv         TEXT NOT NULL,
  tag        TEXT NOT NULL,
  synced_at  TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_events_install
  ON behavior_events(install_id, day_date);
