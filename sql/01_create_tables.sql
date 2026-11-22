-- Active: 1786633896542@@127.0.0.1@5432@music_playlist_sql_project
-- ============================================================================
-- Music Store Database - Schema Definition
-- ============================================================================
-- Target DBMS : PostgreSQL 12+
-- Purpose     : Recreates the 11-table music store schema in dependency order.
-- Source      : data/raw/Music_Store_database.sql (original pg_dump-style file)
--
-- Notes
--   * IDs in the source CSVs are integers, so all ID columns are INTEGER.
--   * invoice.billing_postal_code matches the CSV header (the raw dump called
--     it billing_postal).
--   * employee.levels is kept even though the ERD omits it; the analysis
--     queries depend on it to rank employees by seniority.
--   * playlist_track has no surrogate key in the source data, so it uses a
--     composite primary key (playlist_id, track_id).
--   * Run this script against an empty database. The DROP block makes it safe
--     to re-run while developing.
-- ============================================================================

-- Drop children before parents so the script can be re-run cleanly.
DROP TABLE IF EXISTS invoice_line   CASCADE;
DROP TABLE IF EXISTS invoice        CASCADE;
DROP TABLE IF EXISTS playlist_track CASCADE;
DROP TABLE IF EXISTS playlist       CASCADE;
DROP TABLE IF EXISTS track          CASCADE;
DROP TABLE IF EXISTS album          CASCADE;
DROP TABLE IF EXISTS artist         CASCADE;
DROP TABLE IF EXISTS genre          CASCADE;
DROP TABLE IF EXISTS media_type     CASCADE;
DROP TABLE IF EXISTS customer       CASCADE;
DROP TABLE IF EXISTS employee       CASCADE;

-- ----------------------------------------------------------------------------
-- Reference / dimension tables
-- ----------------------------------------------------------------------------

CREATE TABLE artist (
    artist_id   INTEGER      PRIMARY KEY,
    name        VARCHAR(120) NOT NULL
);

CREATE TABLE album (
    album_id    INTEGER      PRIMARY KEY,
    title       VARCHAR(160) NOT NULL,
    artist_id   INTEGER      NOT NULL REFERENCES artist (artist_id)
);

CREATE TABLE genre (
    genre_id    INTEGER      PRIMARY KEY,
    name        VARCHAR(120) NOT NULL
);

CREATE TABLE media_type (
    media_type_id INTEGER    PRIMARY KEY,
    name          VARCHAR(120) NOT NULL
);

-- ----------------------------------------------------------------------------
-- Core catalog
-- ----------------------------------------------------------------------------

CREATE TABLE track (
    track_id        INTEGER      PRIMARY KEY,
    name            VARCHAR(200) NOT NULL,
    album_id        INTEGER      REFERENCES album (album_id),
    media_type_id   INTEGER      REFERENCES media_type (media_type_id),
    genre_id        INTEGER      REFERENCES genre (genre_id),
    composer        VARCHAR(220),
    milliseconds    INTEGER      CHECK (milliseconds >= 0),
    bytes           BIGINT       CHECK (bytes >= 0),
    unit_price      NUMERIC(10, 2) NOT NULL DEFAULT 0.99 CHECK (unit_price >= 0)
);

CREATE TABLE playlist (
    playlist_id INTEGER      PRIMARY KEY,
    name        VARCHAR(120) NOT NULL
);

CREATE TABLE playlist_track (
    playlist_id INTEGER NOT NULL REFERENCES playlist (playlist_id) ON DELETE CASCADE,
    track_id    INTEGER NOT NULL REFERENCES track (track_id)    ON DELETE CASCADE,
    PRIMARY KEY (playlist_id, track_id)
);

-- ----------------------------------------------------------------------------
-- People and sales
-- ----------------------------------------------------------------------------

CREATE TABLE employee (
    employee_id INTEGER      PRIMARY KEY,
    last_name   VARCHAR(50)  NOT NULL,
    first_name  VARCHAR(50)  NOT NULL,
    title       VARCHAR(50),
    -- Deferred so the CSV can be loaded in file order: the first row reports
    -- to an employee that appears later in the file.
    reports_to  INTEGER      REFERENCES employee (employee_id)
                             DEFERRABLE INITIALLY DEFERRED,
    levels      VARCHAR(10),
    birthdate   TIMESTAMP,
    hire_date   TIMESTAMP,
    address     VARCHAR(120),
    city        VARCHAR(50),
    state       VARCHAR(50),
    country     VARCHAR(50),
    postal_code VARCHAR(30),
    phone       VARCHAR(30),
    fax         VARCHAR(30),
    email       VARCHAR(60)
);

CREATE TABLE customer (
    customer_id     INTEGER      PRIMARY KEY,
    first_name      VARCHAR(50)  NOT NULL,
    last_name       VARCHAR(50)  NOT NULL,
    company         VARCHAR(120),
    address         VARCHAR(120),
    city            VARCHAR(50),
    state           VARCHAR(50),
    country         VARCHAR(50),
    postal_code     VARCHAR(50),
    phone           VARCHAR(50),
    fax             VARCHAR(50),
    email           VARCHAR(60)  NOT NULL,
    support_rep_id  INTEGER      REFERENCES employee (employee_id)
);

CREATE TABLE invoice (
    invoice_id           INTEGER      PRIMARY KEY,
    customer_id          INTEGER      NOT NULL REFERENCES customer (customer_id),
    invoice_date         TIMESTAMP    NOT NULL,
    billing_address      VARCHAR(120),
    billing_city         VARCHAR(50),
    billing_state        VARCHAR(50),
    billing_country      VARCHAR(50),
    billing_postal_code  VARCHAR(50),
    total                NUMERIC(10, 2) NOT NULL DEFAULT 0 CHECK (total >= 0)
);

CREATE TABLE invoice_line (
    invoice_line_id INTEGER      PRIMARY KEY,
    invoice_id      INTEGER      NOT NULL REFERENCES invoice (invoice_id) ON DELETE CASCADE,
    track_id        INTEGER      NOT NULL REFERENCES track (track_id),
    unit_price      NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0),
    quantity        SMALLINT     NOT NULL DEFAULT 1 CHECK (quantity > 0)
);

-- ----------------------------------------------------------------------------
-- Indexes on foreign keys used by the analysis queries
-- (PostgreSQL does not create these automatically.)
-- ----------------------------------------------------------------------------

CREATE INDEX idx_album_artist          ON album (artist_id);
CREATE INDEX idx_track_album           ON track (album_id);
CREATE INDEX idx_track_genre           ON track (genre_id);
CREATE INDEX idx_track_media_type      ON track (media_type_id);
CREATE INDEX idx_customer_support_rep  ON customer (support_rep_id);
CREATE INDEX idx_invoice_customer      ON invoice (customer_id);
CREATE INDEX idx_invoice_date          ON invoice (invoice_date);
CREATE INDEX idx_invoice_line_invoice  ON invoice_line (invoice_id);
CREATE INDEX idx_invoice_line_track    ON invoice_line (track_id);
CREATE INDEX idx_playlist_track_track  ON playlist_track (track_id);

COMMENT ON TABLE playlist_track IS 'Many-to-many link between playlists and tracks.';
COMMENT ON COLUMN employee.levels IS 'Seniority band (L1-L7); used to find the most senior employee.';
COMMENT ON COLUMN invoice.billing_postal_code IS 'Postal code recorded on the invoice (CSV header: billing_postal_code).';
