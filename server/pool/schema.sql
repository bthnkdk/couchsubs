-- Subtitle pool: oyuncuların okuduğu, paketlerde olmayan İngilizce satırlar.
-- IP, kullanıcı adı ya da PSN bilgisi tutulmaz; yalnız rastgele kurulum kimliği.
CREATE TABLE IF NOT EXISTS lines (
  key TEXT PRIMARY KEY,          -- canon(text) SHA-256 ilk 16 hex
  text TEXT NOT NULL,            -- ilk gelen okuma
  installs INTEGER NOT NULL DEFAULT 0,  -- kaç farklı kurulum gördü
  first_seen TEXT NOT NULL,
  last_seen TEXT NOT NULL,
  exported INTEGER NOT NULL DEFAULT 0   -- çeviriye alındı mı
);
CREATE INDEX IF NOT EXISTS lines_installs ON lines(installs, exported);

CREATE TABLE IF NOT EXISTS sightings (
  key TEXT NOT NULL,
  install TEXT NOT NULL,
  PRIMARY KEY (key, install)
);

CREATE TABLE IF NOT EXISTS quota (
  install TEXT NOT NULL,
  day TEXT NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (install, day)
);
