SELECT current_database(), current_user;-- =============================================================

SELECT *
FROM telecom_tower_summary;

-- TELECOM NETWORK OUTAGE & RELIABILITY ANALYTICS
-- Consolidated SQL Pipeline (PostgreSQL)
-- Run in order: raw load -> inspection -> quality -> validation
-- -> outliers -> cleaning -> feature engineering -> business analysis
-- =============================================================


-- ================================================================
-- FILE: 01_create_raw_table.sql
-- ================================================================
-- =====================================================================
-- PHASE 1 - STEP 0: RAW TABLE CREATION
-- Purpose: Preserve the original dataset exactly as received.
-- Rule: telecom_outage_raw is NEVER modified after this load.
-- Text columns loaded as TEXT (not VARCHAR with implicit trimming) so
-- that whitespace/casing issues are preserved for the Step 2 audit.
-- Numeric/date columns loaded using the source's native types since the
-- parquet inspection showed clean, structurally valid types (no parsing
-- failures) - this is a faithful load, not a cleaning step.
-- =====================================================================

DROP TABLE IF EXISTS telecom_outage_raw;

CREATE TABLE telecom_outage_raw (
    row_id              SERIAL PRIMARY KEY,   -- surrogate key for traceability, not part of source data
    tower_id            TEXT,
    obs_date            TEXT,                 -- kept as TEXT at raw layer; cast/validated in Step 2/3
    operator            TEXT,
    city                TEXT,
    state               TEXT,
    uptime_percentage   TEXT,                 -- kept as TEXT at raw layer to catch any non-numeric junk
    downtime_minutes    TEXT,
    outage_count        TEXT,
    outage_reason       TEXT,
    network_type        TEXT,
    avg_users_affected  TEXT
);

COMMENT ON TABLE telecom_outage_raw IS 'Untouched raw load of base_station_uptime_logs. Preserved for lineage/reproducibility. Never updated or deleted from.';

-- ---------------------------------------------------------------------
-- LOAD: this was originally run as a one-off \COPY command and is
-- restored here so the script is actually runnable end-to-end.
-- Prerequisite: place the source file at data/base_station_uptime_logs_clean.csv
-- (headers: tower_id,date,operator,city,state,uptime_percentage,
-- downtime_minutes,outage_count,outage_reason,network_type,
-- avg_users_affected). NULLs must be empty strings, not the word NULL.
-- ---------------------------------------------------------------------
\COPY telecom_outage_raw (tower_id, obs_date, operator, city, state, uptime_percentage, downtime_minutes, outage_count, outage_reason, network_type, avg_users_affected) FROM 'data/base_station_uptime_logs_clean.csv' WITH (FORMAT csv, HEADER true, NULL '');

-- Sanity check: should return 100000 after a successful load
SELECT COUNT(*) AS raw_row_count FROM telecom_outage_raw;


-- ================================================================
-- FILE: 02_step1_data_inspection.sql
-- ================================================================
-- =====================================================================
-- STEP 1: DATA INSPECTION
-- Purpose: Understand the raw dataset's shape, structure, and grain
-- before any cleaning decisions are made.
-- =====================================================================

-- 1.1 Row count
SELECT COUNT(*) AS total_rows FROM telecom_outage_raw;

-- 1.2 Column names and data types (as loaded, all TEXT at raw layer)
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'telecom_outage_raw'
ORDER BY ordinal_position;

-- 1.3 Sample records
SELECT * FROM telecom_outage_raw ORDER BY row_id LIMIT 5;

-- 1.4 Unique towers
SELECT COUNT(DISTINCT tower_id) AS unique_towers FROM telecom_outage_raw;

-- 1.5 Unique operators
SELECT DISTINCT operator FROM telecom_outage_raw ORDER BY operator;

-- 1.6 Unique states
SELECT COUNT(DISTINCT state) AS unique_states FROM telecom_outage_raw;

-- 1.7 Unique cities
SELECT COUNT(DISTINCT city) AS unique_cities FROM telecom_outage_raw;

-- 1.8 Network types
SELECT DISTINCT network_type FROM telecom_outage_raw ORDER BY network_type;

-- 1.9 Outage reasons (including NULL)
SELECT outage_reason, COUNT(*) AS n
FROM telecom_outage_raw
GROUP BY outage_reason
ORDER BY n DESC;

-- 1.10 Min / max dates (cast for inspection only; raw column stays TEXT)
SELECT MIN(obs_date::date) AS min_date, MAX(obs_date::date) AS max_date
FROM telecom_outage_raw;

-- 1.11 Grain check: rows per (tower_id, obs_date)
SELECT rows_per_key, COUNT(*) AS num_towers_dates
FROM (
    SELECT tower_id, obs_date, COUNT(*) AS rows_per_key
    FROM telecom_outage_raw
    GROUP BY tower_id, obs_date
) t
GROUP BY rows_per_key
ORDER BY rows_per_key;

-- 1.12 Rows per tower distribution (how many distinct dates does each tower have?)
SELECT rows_per_tower, COUNT(*) AS num_towers
FROM (
    SELECT tower_id, COUNT(*) AS rows_per_tower
    FROM telecom_outage_raw
    GROUP BY tower_id
) t
GROUP BY rows_per_tower
ORDER BY rows_per_tower;


-- ================================================================
-- FILE: 03_step2_data_quality.sql
-- ================================================================
-- =====================================================================
-- STEP 2: DATA QUALITY ASSESSMENT
-- Purpose: Identify issues WITHOUT fixing them yet. Nothing here
-- modifies telecom_outage_raw. Findings drive Step 5 cleaning decisions.
-- =====================================================================

-- 2.1 NULL values per column
SELECT
    COUNT(*) FILTER (WHERE tower_id IS NULL)           AS null_tower_id,
    COUNT(*) FILTER (WHERE obs_date IS NULL)            AS null_obs_date,
    COUNT(*) FILTER (WHERE operator IS NULL)            AS null_operator,
    COUNT(*) FILTER (WHERE city IS NULL)                AS null_city,
    COUNT(*) FILTER (WHERE state IS NULL)               AS null_state,
    COUNT(*) FILTER (WHERE uptime_percentage IS NULL)   AS null_uptime,
    COUNT(*) FILTER (WHERE downtime_minutes IS NULL)    AS null_downtime,
    COUNT(*) FILTER (WHERE outage_count IS NULL)        AS null_outage_count,
    COUNT(*) FILTER (WHERE outage_reason IS NULL)       AS null_outage_reason,
    COUNT(*) FILTER (WHERE network_type IS NULL)        AS null_network_type,
    COUNT(*) FILTER (WHERE avg_users_affected IS NULL)  AS null_avg_users_affected
FROM telecom_outage_raw;

-- 2.2 Blank / whitespace-only strings (distinct from NULL)
SELECT
    COUNT(*) FILTER (WHERE tower_id IS NOT NULL AND TRIM(tower_id) = '')   AS blank_tower_id,
    COUNT(*) FILTER (WHERE operator IS NOT NULL AND TRIM(operator) = '')  AS blank_operator,
    COUNT(*) FILTER (WHERE city IS NOT NULL AND TRIM(city) = '')          AS blank_city,
    COUNT(*) FILTER (WHERE state IS NOT NULL AND TRIM(state) = '')        AS blank_state,
    COUNT(*) FILTER (WHERE network_type IS NOT NULL AND TRIM(network_type) = '') AS blank_network_type
FROM telecom_outage_raw;

-- 2.3 Leading/trailing whitespace present (value differs from TRIM(value))
SELECT
    COUNT(*) FILTER (WHERE tower_id <> TRIM(tower_id))     AS ws_tower_id,
    COUNT(*) FILTER (WHERE operator <> TRIM(operator))     AS ws_operator,
    COUNT(*) FILTER (WHERE city <> TRIM(city))             AS ws_city,
    COUNT(*) FILTER (WHERE state <> TRIM(state))           AS ws_state,
    COUNT(*) FILTER (WHERE network_type <> TRIM(network_type)) AS ws_network_type,
    COUNT(*) FILTER (WHERE outage_reason IS NOT NULL AND outage_reason <> TRIM(outage_reason)) AS ws_outage_reason
FROM telecom_outage_raw;

-- 2.4 Inconsistent capitalization: does casefolding change the distinct-value count?
SELECT 'operator' AS col, COUNT(DISTINCT operator) AS raw_distinct, COUNT(DISTINCT LOWER(TRIM(operator))) AS lower_distinct FROM telecom_outage_raw
UNION ALL
SELECT 'city', COUNT(DISTINCT city), COUNT(DISTINCT LOWER(TRIM(city))) FROM telecom_outage_raw
UNION ALL
SELECT 'state', COUNT(DISTINCT state), COUNT(DISTINCT LOWER(TRIM(state))) FROM telecom_outage_raw
UNION ALL
SELECT 'network_type', COUNT(DISTINCT network_type), COUNT(DISTINCT LOWER(TRIM(network_type))) FROM telecom_outage_raw
UNION ALL
SELECT 'outage_reason', COUNT(DISTINCT outage_reason), COUNT(DISTINCT LOWER(TRIM(outage_reason))) FROM telecom_outage_raw;

-- 2.5 Exact duplicate full rows (excluding surrogate row_id)
SELECT COUNT(*) AS duplicate_full_rows
FROM (
    SELECT tower_id, obs_date, operator, city, state, uptime_percentage,
           downtime_minutes, outage_count, outage_reason, network_type, avg_users_affected,
           COUNT(*) AS cnt
    FROM telecom_outage_raw
    GROUP BY tower_id, obs_date, operator, city, state, uptime_percentage,
             downtime_minutes, outage_count, outage_reason, network_type, avg_users_affected
    HAVING COUNT(*) > 1
) d;

-- 2.6 Duplicate (tower_id, obs_date) pairs - and whether the duplicate rows
-- have identical or DIFFERING measures (tells us if it's a true duplicate
-- or two distinct readings sharing a key)
SELECT tower_id, obs_date, COUNT(*) AS n,
       COUNT(DISTINCT uptime_percentage) AS distinct_uptime_values,
       COUNT(DISTINCT downtime_minutes)  AS distinct_downtime_values,
       COUNT(DISTINCT outage_count)      AS distinct_outage_count_values
FROM telecom_outage_raw
GROUP BY tower_id, obs_date
HAVING COUNT(*) > 1
ORDER BY n DESC
LIMIT 20;

-- 2.7 Invalid tower_id format check (expected pattern: 3 letters, dash, digits)
SELECT COUNT(*) AS invalid_tower_id_format
FROM telecom_outage_raw
WHERE tower_id !~ '^[A-Za-z]{3}-[0-9]+$';

-- 2.8 Distinct operator / network_type / outage_reason values verbatim (case/space sensitive)
SELECT DISTINCT operator FROM telecom_outage_raw ORDER BY 1;
SELECT DISTINCT network_type FROM telecom_outage_raw ORDER BY 1;
SELECT DISTINCT outage_reason FROM telecom_outage_raw ORDER BY 1;

-- 2.9 City / State verbatim distinct lists (to check for inconsistent naming, not just casing)
SELECT DISTINCT city FROM telecom_outage_raw ORDER BY 1;
SELECT DISTINCT state FROM telecom_outage_raw ORDER BY 1;

-- 2.10 Invalid dates: rows where obs_date does not parse as a valid date
SELECT COUNT(*) AS unparseable_dates
FROM telecom_outage_raw
WHERE obs_date IS NULL
   OR obs_date !~ '^\d{4}-\d{2}-\d{2}$';

-- 2.11 Non-numeric junk in numeric-looking columns
SELECT
    COUNT(*) FILTER (WHERE uptime_percentage !~ '^-?\d+(\.\d+)?$')  AS bad_uptime_format,
    COUNT(*) FILTER (WHERE downtime_minutes !~ '^-?\d+(\.\d+)?$')  AS bad_downtime_format,
    COUNT(*) FILTER (WHERE outage_count !~ '^-?\d+$')              AS bad_outage_count_format,
    COUNT(*) FILTER (WHERE avg_users_affected !~ '^-?\d+$')        AS bad_avg_users_format
FROM telecom_outage_raw;

-- 2.12 city/state combination consistency: does each city map to exactly
-- one state? (tests whether "State -> City" is a true hierarchy)
SELECT city, COUNT(DISTINCT state) AS distinct_states_for_city
FROM telecom_outage_raw
GROUP BY city
ORDER BY distinct_states_for_city DESC;


-- ================================================================
-- FILE: 04_step3_numeric_validation.sql
-- ================================================================
-- =====================================================================
-- STEP 3: NUMERIC VALIDATION
-- Purpose: Flag suspicious/invalid numeric values. Nothing is removed.
-- Casts are done inline for validation only; telecom_outage_raw stays TEXT.
-- =====================================================================

-- 3.1 uptime_percentage should be between 0 and 100
SELECT COUNT(*) AS uptime_out_of_range
FROM telecom_outage_raw
WHERE uptime_percentage::numeric < 0 OR uptime_percentage::numeric > 100;

SELECT MIN(uptime_percentage::numeric) AS min_uptime, MAX(uptime_percentage::numeric) AS max_uptime
FROM telecom_outage_raw;

-- 3.2 downtime_minutes should be >= 0
SELECT COUNT(*) AS downtime_negative
FROM telecom_outage_raw
WHERE downtime_minutes::numeric < 0;

SELECT MIN(downtime_minutes::numeric) AS min_downtime, MAX(downtime_minutes::numeric) AS max_downtime
FROM telecom_outage_raw;

-- 3.3 outage_count should be >= 0
SELECT COUNT(*) AS outage_count_negative
FROM telecom_outage_raw
WHERE outage_count::numeric < 0;

SELECT MIN(outage_count::numeric) AS min_outage_count, MAX(outage_count::numeric) AS max_outage_count
FROM telecom_outage_raw;

-- 3.4 avg_users_affected should be >= 0
SELECT COUNT(*) AS users_affected_negative
FROM telecom_outage_raw
WHERE avg_users_affected::numeric < 0;

SELECT MIN(avg_users_affected::numeric) AS min_users, MAX(avg_users_affected::numeric) AS max_users
FROM telecom_outage_raw;

-- 3.5 CROSS-FIELD LOGICAL CHECKS (not requested verbatim in blueprint numeric
-- validation, but necessary to validate internal consistency of the measures)

-- 3.5a outage_count = 0 but downtime_minutes > 0 (outage-free day with downtime?)
SELECT COUNT(*) AS zero_outages_but_downtime
FROM telecom_outage_raw
WHERE outage_count::numeric = 0 AND downtime_minutes::numeric > 0;

-- 3.5b outage_count > 0 but downtime_minutes = 0 (outages recorded with zero downtime?)
SELECT COUNT(*) AS outages_but_zero_downtime
FROM telecom_outage_raw
WHERE outage_count::numeric > 0 AND downtime_minutes::numeric = 0;

-- 3.5c outage_count = 0 AND avg_users_affected > 0 (no outage but users affected?)
SELECT COUNT(*) AS zero_outages_but_users_affected
FROM telecom_outage_raw
WHERE outage_count::numeric = 0 AND avg_users_affected::numeric > 0;

-- 3.5d outage_count > 0 AND avg_users_affected = 0 (outage with zero users affected -
-- plausible for very short/minor outages, just checking prevalence)
SELECT COUNT(*) AS outages_but_zero_users_affected
FROM telecom_outage_raw
WHERE outage_count::numeric > 0 AND avg_users_affected::numeric = 0;

-- 3.5e outage_reason present but outage_count = 0 (a cause logged with no outage?)
SELECT COUNT(*) AS reason_present_but_zero_outage_count
FROM telecom_outage_raw
WHERE outage_reason IS NOT NULL AND outage_count::numeric = 0;

-- 3.5f outage_reason NULL but outage_count > 0 (outage happened, cause not captured)
SELECT COUNT(*) AS null_reason_but_outage_occurred
FROM telecom_outage_raw
WHERE outage_reason IS NULL AND outage_count::numeric > 0;

-- 3.5g Relationship check: does higher downtime correlate with lower uptime,
-- as expected? Simple sanity check via correlation (Pearson, computed in SQL)
SELECT corr(uptime_percentage::numeric, downtime_minutes::numeric) AS corr_uptime_downtime,
       corr(downtime_minutes::numeric, outage_count::numeric) AS corr_downtime_outagecount,
       corr(outage_count::numeric, avg_users_affected::numeric) AS corr_outagecount_users
FROM telecom_outage_raw;

-- 3.6 Distribution deciles for context (helps spot skew ahead of outlier step)
SELECT
    percentile_cont(0.01) WITHIN GROUP (ORDER BY uptime_percentage::numeric) AS p01_uptime,
    percentile_cont(0.99) WITHIN GROUP (ORDER BY uptime_percentage::numeric) AS p99_uptime,
    percentile_cont(0.01) WITHIN GROUP (ORDER BY downtime_minutes::numeric) AS p01_downtime,
    percentile_cont(0.99) WITHIN GROUP (ORDER BY downtime_minutes::numeric) AS p99_downtime,
    percentile_cont(0.99) WITHIN GROUP (ORDER BY avg_users_affected::numeric) AS p99_users
FROM telecom_outage_raw;


-- ================================================================
-- FILE: 05_step4_outlier_analysis.sql
-- ================================================================
-- =====================================================================
-- STEP 4: OUTLIER ANALYSIS
-- Purpose: Investigate extreme values before deciding on treatment.
-- Uses IQR method (standard, non-fabricated statistical technique).
-- Nothing is removed here - this is investigation only.
-- =====================================================================

-- 4.1 IQR bounds for each numeric measure
WITH stats AS (
    SELECT
        percentile_cont(0.25) WITHIN GROUP (ORDER BY uptime_percentage::numeric) AS q1_uptime,
        percentile_cont(0.75) WITHIN GROUP (ORDER BY uptime_percentage::numeric) AS q3_uptime,
        percentile_cont(0.25) WITHIN GROUP (ORDER BY downtime_minutes::numeric) AS q1_downtime,
        percentile_cont(0.75) WITHIN GROUP (ORDER BY downtime_minutes::numeric) AS q3_downtime,
        percentile_cont(0.25) WITHIN GROUP (ORDER BY outage_count::numeric) AS q1_outage,
        percentile_cont(0.75) WITHIN GROUP (ORDER BY outage_count::numeric) AS q3_outage,
        percentile_cont(0.25) WITHIN GROUP (ORDER BY avg_users_affected::numeric) AS q1_users,
        percentile_cont(0.75) WITHIN GROUP (ORDER BY avg_users_affected::numeric) AS q3_users
    FROM telecom_outage_raw
)
SELECT
    q1_uptime, q3_uptime, (q3_uptime - q1_uptime) AS iqr_uptime,
    q1_uptime - 1.5*(q3_uptime-q1_uptime) AS lower_fence_uptime,
    q3_uptime + 1.5*(q3_uptime-q1_uptime) AS upper_fence_uptime,
    q1_downtime, q3_downtime, (q3_downtime - q1_downtime) AS iqr_downtime,
    q1_downtime - 1.5*(q3_downtime-q1_downtime) AS lower_fence_downtime,
    q3_downtime + 1.5*(q3_downtime-q1_downtime) AS upper_fence_downtime,
    q1_outage, q3_outage,
    q1_outage - 1.5*(q3_outage-q1_outage) AS lower_fence_outage,
    q3_outage + 1.5*(q3_outage-q1_outage) AS upper_fence_outage,
    q1_users, q3_users,
    q1_users - 1.5*(q3_users-q1_users) AS lower_fence_users,
    q3_users + 1.5*(q3_users-q1_users) AS upper_fence_users
FROM stats;

-- 4.2 Count of IQR-flagged outliers per measure
WITH stats AS (
    SELECT
        percentile_cont(0.25) WITHIN GROUP (ORDER BY uptime_percentage::numeric) AS q1_u,
        percentile_cont(0.75) WITHIN GROUP (ORDER BY uptime_percentage::numeric) AS q3_u,
        percentile_cont(0.25) WITHIN GROUP (ORDER BY downtime_minutes::numeric) AS q1_d,
        percentile_cont(0.75) WITHIN GROUP (ORDER BY downtime_minutes::numeric) AS q3_d,
        percentile_cont(0.25) WITHIN GROUP (ORDER BY outage_count::numeric) AS q1_o,
        percentile_cont(0.75) WITHIN GROUP (ORDER BY outage_count::numeric) AS q3_o,
        percentile_cont(0.25) WITHIN GROUP (ORDER BY avg_users_affected::numeric) AS q1_a,
        percentile_cont(0.75) WITHIN GROUP (ORDER BY avg_users_affected::numeric) AS q3_a
    FROM telecom_outage_raw
)
SELECT
    (SELECT COUNT(*) FROM telecom_outage_raw, stats
        WHERE uptime_percentage::numeric < q1_u-1.5*(q3_u-q1_u) OR uptime_percentage::numeric > q3_u+1.5*(q3_u-q1_u)) AS outliers_uptime,
    (SELECT COUNT(*) FROM telecom_outage_raw, stats
        WHERE downtime_minutes::numeric < q1_d-1.5*(q3_d-q1_d) OR downtime_minutes::numeric > q3_d+1.5*(q3_d-q1_d)) AS outliers_downtime,
    (SELECT COUNT(*) FROM telecom_outage_raw, stats
        WHERE outage_count::numeric < q1_o-1.5*(q3_o-q1_o) OR outage_count::numeric > q3_o+1.5*(q3_o-q1_o)) AS outliers_outage_count,
    (SELECT COUNT(*) FROM telecom_outage_raw, stats
        WHERE avg_users_affected::numeric < q1_a-1.5*(q3_a-q1_a) OR avg_users_affected::numeric > q3_a+1.5*(q3_a-q1_a)) AS outliers_users;

-- 4.3 Look at the extreme tail of downtime_minutes directly (max is 216 - is
-- that a hard cap, i.e. a data-generation ceiling rather than a true outlier?)
SELECT downtime_minutes, COUNT(*) AS n
FROM telecom_outage_raw
WHERE downtime_minutes::numeric > 200
GROUP BY downtime_minutes
ORDER BY downtime_minutes::numeric DESC
LIMIT 15;

-- 4.4 Histogram-style bucket check across the FULL range of downtime_minutes
-- to see if the distribution is smooth (natural) or has a suspicious hard
-- ceiling/floor (generation artifact)
SELECT width_bucket(downtime_minutes::numeric, 0, 220, 22) AS bucket,
       MIN(downtime_minutes::numeric) AS bucket_min, MAX(downtime_minutes::numeric) AS bucket_max,
       COUNT(*) AS n
FROM telecom_outage_raw
GROUP BY bucket
ORDER BY bucket;

-- 4.5 Same check for uptime_percentage floor (min observed was 85.0 - is 85 a hard floor?)
SELECT width_bucket(uptime_percentage::numeric, 85, 100, 15) AS bucket,
       MIN(uptime_percentage::numeric) AS bucket_min, MAX(uptime_percentage::numeric) AS bucket_max,
       COUNT(*) AS n
FROM telecom_outage_raw
GROUP BY bucket
ORDER BY bucket;

-- 4.6 avg_users_affected: is 500 a hard ceiling? and how many true zeros?
SELECT
    COUNT(*) FILTER (WHERE avg_users_affected::numeric = 0) AS exactly_zero,
    COUNT(*) FILTER (WHERE avg_users_affected::numeric = 500) AS exactly_500_cap,
    MAX(avg_users_affected::numeric) AS max_val
FROM telecom_outage_raw;

-- 4.7 outage_count: is 5 a hard ceiling?
SELECT outage_count, COUNT(*) AS n
FROM telecom_outage_raw
GROUP BY outage_count
ORDER BY outage_count::numeric;


-- ================================================================
-- FILE: 06_step5_data_cleaning.sql
-- ================================================================
-- =====================================================================
-- STEP 5: DATA CLEANING
-- Purpose: Produce telecom_outage_clean - a typed, analysis-ready table.
-- telecom_outage_raw is NEVER modified. Every decision below is
-- documented with its rationale.
-- =====================================================================

DROP TABLE IF EXISTS telecom_outage_clean;

CREATE TABLE telecom_outage_clean AS
SELECT
    row_id,
    TRIM(tower_id)                       AS tower_id,        -- defensive TRIM; Step 2 found 0 whitespace issues, applied for reproducibility safety
    obs_date::date                       AS obs_date,         -- validated as 100% parseable in Step 2 (2.10)
    TRIM(operator)                       AS operator,         -- defensive TRIM; 0 casing/whitespace issues found
    TRIM(city)                           AS city,             -- defensive TRIM; 0 casing/whitespace issues found
    TRIM(state)                          AS state,            -- defensive TRIM; 0 casing/whitespace issues found
    uptime_percentage::numeric(6,2)      AS uptime_percentage,-- validated 0-100 in Step 3
    downtime_minutes::numeric(8,2)       AS downtime_minutes, -- validated >=0 in Step 3
    outage_count::int                    AS outage_count,     -- validated >=0 in Step 3
    NULLIF(TRIM(outage_reason), '')      AS outage_reason,    -- NULL preserved deliberately (see decision log below); not imputed
    TRIM(network_type)                   AS network_type,     -- defensive TRIM; 0 casing/whitespace issues found
    avg_users_affected::int              AS avg_users_affected
FROM telecom_outage_raw;

-- Row count reconciliation: clean table must retain all 100,000 raw rows
-- (per project rule: do not automatically delete missing values or outliers)
SELECT
    (SELECT COUNT(*) FROM telecom_outage_raw)   AS raw_row_count,
    (SELECT COUNT(*) FROM telecom_outage_clean) AS clean_row_count;

-- Add primary key + helpful indexes for downstream SQL analysis
ALTER TABLE telecom_outage_clean ADD PRIMARY KEY (row_id);
CREATE INDEX idx_clean_tower_date ON telecom_outage_clean (tower_id, obs_date);
CREATE INDEX idx_clean_operator   ON telecom_outage_clean (operator);
CREATE INDEX idx_clean_state      ON telecom_outage_clean (state);
CREATE INDEX idx_clean_network    ON telecom_outage_clean (network_type);

COMMENT ON TABLE telecom_outage_clean IS
'Typed, analysis-ready version of telecom_outage_raw. No rows removed, no values imputed. See project data-cleaning decision log for rationale on outage_reason nulls, duplicate tower/date keys, and outlier treatment.';

-- Final validation: re-run the core numeric range checks against the clean table
SELECT
    MIN(uptime_percentage) AS min_uptime, MAX(uptime_percentage) AS max_uptime,
    MIN(downtime_minutes)  AS min_downtime, MAX(downtime_minutes) AS max_downtime,
    MIN(outage_count)      AS min_outage_count, MAX(outage_count) AS max_outage_count,
    MIN(avg_users_affected) AS min_users, MAX(avg_users_affected) AS max_users,
    MIN(obs_date) AS min_date, MAX(obs_date) AS max_date
FROM telecom_outage_clean;


-- ================================================================
-- FILE: 07_step6_date_features.sql
-- ================================================================
-- =====================================================================
-- STEP 6: DATE FEATURE ENGINEERING
-- Purpose: Derive standard calendar attributes from obs_date.
-- Applied on top of telecom_outage_clean; clean table itself untouched.
-- =====================================================================

DROP TABLE IF EXISTS telecom_outage_features;

CREATE TABLE telecom_outage_features AS
SELECT
    c.*,
    EXTRACT(YEAR FROM obs_date)::int                    AS obs_year,
    EXTRACT(QUARTER FROM obs_date)::int                 AS obs_quarter,
    EXTRACT(MONTH FROM obs_date)::int                   AS obs_month_number,
    TRIM(TO_CHAR(obs_date, 'Month'))                    AS obs_month_name,
    EXTRACT(WEEK FROM obs_date)::int                    AS obs_week_number,      -- ISO week number
    TRIM(TO_CHAR(obs_date, 'Day'))                      AS obs_day_of_week_name,
    EXTRACT(ISODOW FROM obs_date)::int                  AS obs_day_of_week_number, -- 1=Mon .. 7=Sun
    CASE WHEN EXTRACT(ISODOW FROM obs_date) IN (6,7) THEN TRUE ELSE FALSE END AS is_weekend
FROM telecom_outage_clean c;

-- Row count check
SELECT COUNT(*) FROM telecom_outage_features;

-- Sanity check on distribution of new fields (given the ~31-day window)
SELECT obs_year, obs_quarter, obs_month_number, obs_month_name, COUNT(*) AS n
FROM telecom_outage_features
GROUP BY obs_year, obs_quarter, obs_month_number, obs_month_name
ORDER BY 1,2,3;

SELECT obs_day_of_week_name, obs_day_of_week_number, is_weekend, COUNT(*) AS n
FROM telecom_outage_features
GROUP BY 1,2,3
ORDER BY obs_day_of_week_number;


-- ================================================================
-- FILE: 08_step7a_row_features.sql
-- ================================================================
-- STEP 7a: ROW-LEVEL FEATURES ALIGNED TO PYTHON/CHART OUTPUTS
ALTER TABLE telecom_outage_features
    ADD COLUMN reliability_status TEXT,
    ADD COLUMN high_risk_flag INTEGER,
    ADD COLUMN downtime_hours NUMERIC,
    ADD COLUMN observation_month TEXT,
    ADD COLUMN day_of_week TEXT,
    ADD COLUMN outage_severity TEXT;

UPDATE telecom_outage_features SET
reliability_status = CASE
    WHEN uptime_percentage >= 99 THEN 'Excellent'
    WHEN uptime_percentage >= 95 THEN 'Good'
    WHEN uptime_percentage >= 90 THEN 'Fair'
    ELSE 'Poor' END,
high_risk_flag = CASE WHEN uptime_percentage < 95 THEN 1 ELSE 0 END,
downtime_hours = ROUND((downtime_minutes / 60.0)::numeric, 4),
observation_month = TO_CHAR(obs_date, 'YYYY-MM'),
day_of_week = TRIM(TO_CHAR(obs_date, 'Day')),
outage_severity = CASE
    WHEN downtime_minutes >= 120 OR outage_count >= 4 THEN 'High'
    WHEN downtime_minutes >= 60 OR outage_count >= 2 THEN 'Medium'
    ELSE 'Low' END;

-- Published-export validation
SELECT reliability_status, COUNT(*) FROM telecom_outage_features GROUP BY 1 ORDER BY 1;
SELECT outage_severity, COUNT(*) FROM telecom_outage_features GROUP BY 1 ORDER BY 1;
SELECT high_risk_flag, COUNT(*) FROM telecom_outage_features GROUP BY 1 ORDER BY 1;

-- ================================================================
-- FILE: 09_step7b_tower_summary.sql
-- ================================================================
-- =====================================================================
-- STEP 7b: OPERATIONAL FEATURES - TOWER LEVEL
-- Purpose: repeat_outage_indicator and a PRELIMINARY site_risk_category.
--
-- CRITICAL DATA-QUALITY FINDING THAT SHAPES THIS DESIGN:
-- tower_id does NOT consistently map to a single operator, state, or
-- network_type across its observations. Confirmed via SQL:
--   - 18,241 of 70,599 towers (25.8%) show more than one operator
--   - 22,599 of 70,599 towers (32.0%) show more than one state
--   - 12,817 of 70,599 towers (18.2%) show more than one network_type
-- However, tower_id's 3-letter prefix maps to `city` with ZERO
-- mismatches (confirmed exhaustively) - city IS a stable attribute of
-- tower_id, but operator/state/network_type are NOT.
--
-- DECISION: tower-level aggregation uses tower_id + city as the stable
-- site identity. operator/state/network_type are summarized using the
-- MODE (most frequent value) purely for labeling/display, with an
-- explicit distinct-value count retained so this instability is never
-- hidden. This is a documented limitation, not a silent assumption.
-- =====================================================================

DROP TABLE IF EXISTS telecom_tower_summary;

CREATE TABLE telecom_tower_summary AS
WITH mode_operator AS (
    SELECT DISTINCT ON (tower_id) tower_id, operator AS mode_operator
    FROM (
        SELECT tower_id, operator, COUNT(*) AS n
        FROM telecom_outage_clean
        GROUP BY tower_id, operator
    ) t
    ORDER BY tower_id, n DESC, operator  -- deterministic tie-break alphabetically
),
mode_network AS (
    SELECT DISTINCT ON (tower_id) tower_id, network_type AS mode_network_type
    FROM (
        SELECT tower_id, network_type, COUNT(*) AS n
        FROM telecom_outage_clean
        GROUP BY tower_id, network_type
    ) t
    ORDER BY tower_id, n DESC, network_type
),
mode_state AS (
    SELECT DISTINCT ON (tower_id) tower_id, state AS mode_state
    FROM (
        SELECT tower_id, state, COUNT(*) AS n
        FROM telecom_outage_clean
        GROUP BY tower_id, state
    ) t
    ORDER BY tower_id, n DESC, state
),
tower_agg AS (
    SELECT
        tower_id,
        MIN(city) AS city,                          -- stable, verified: 1 city per tower_id always
        COUNT(*) AS total_observations,
        COUNT(DISTINCT operator) AS distinct_operator_count,
        COUNT(DISTINCT state) AS distinct_state_count,
        COUNT(DISTINCT network_type) AS distinct_network_type_count,
        ROUND(AVG(uptime_percentage), 2) AS avg_uptime_percentage,
        SUM(downtime_minutes) AS total_downtime_minutes,
        SUM(outage_count) AS total_outage_count,
        SUM(avg_users_affected) AS total_users_affected,
        COUNT(*) FILTER (WHERE avg_users_affected > 0) AS impactful_outage_observations
    FROM telecom_outage_clean
    GROUP BY tower_id
)
SELECT
    a.tower_id,
    a.city,
    mo.mode_operator,
    a.distinct_operator_count,
    ms.mode_state,
    a.distinct_state_count,
    mn.mode_network_type,
    a.distinct_network_type_count,
    a.total_observations,
    a.avg_uptime_percentage,
    a.total_downtime_minutes,
    a.total_outage_count,
    a.total_users_affected,
    a.impactful_outage_observations,
    CASE WHEN a.impactful_outage_observations > 1 THEN 1 ELSE 0 END AS repeat_outage_indicator
FROM tower_agg a
JOIN mode_operator mo ON mo.tower_id = a.tower_id
JOIN mode_state ms ON ms.tower_id = a.tower_id
JOIN mode_network mn ON mn.tower_id = a.tower_id;

-- Row count check: must equal the 70,599 unique towers found in Step 1
SELECT COUNT(*) AS tower_summary_rows FROM telecom_tower_summary;

-- repeat_outage_indicator distribution
SELECT repeat_outage_indicator, COUNT(*) FROM telecom_tower_summary GROUP BY 1;

-- Compute quartile thresholds on the TOWER-LEVEL aggregates for the
-- preliminary risk scoring (data-driven, not arbitrary)
SELECT
    percentile_cont(0.25) WITHIN GROUP (ORDER BY avg_uptime_percentage) AS q1_avg_uptime,
    percentile_cont(0.75) WITHIN GROUP (ORDER BY total_downtime_minutes) AS q3_total_downtime,
    percentile_cont(0.75) WITHIN GROUP (ORDER BY total_users_affected) AS q3_total_users
FROM telecom_tower_summary;


-- ================================================================
-- FILE: 10_step7c_site_risk.sql
-- ================================================================
-- =====================================================================
-- STEP 7c: PRELIMINARY SITE RISK CATEGORY (tower level)
--
-- IMPORTANT: This is a SIMPLE, TRANSPARENT, rule-based preliminary
-- category built here in SQL for early operational reporting. It is
-- explicitly NOT the final Site Reliability/Risk Score - that score
-- (with documented normalization, weighting, and threshold rationale)
-- is built later in the Python analytics phase. This preliminary
-- version exists so early SQL-based business questions (e.g. "how many
-- high-risk towers are there right now") can be answered without
-- waiting for the modeling phase, and its simplicity is deliberate and
-- disclosed - not a substitute for the final score.
--
-- METHOD: 1 point awarded per risk condition met (project-defined,
-- quartile-based thresholds from telecom_tower_summary):
--   +1 if avg_uptime_percentage < 89.44   (below tower-level Q1 uptime)
--   +1 if total_downtime_minutes > 202.32 (above tower-level Q3 downtime)
--   +1 if total_users_affected > 410      (above tower-level Q3 users affected)
--   +1 if repeat_outage_indicator = 1
-- Points summed 0-4, mapped to 4 categories. Equal weighting used
-- because no business-supplied weighting scheme exists at this stage.
-- =====================================================================

ALTER TABLE telecom_tower_summary
    ADD COLUMN risk_points INT,
    ADD COLUMN site_risk_category_preliminary TEXT;

UPDATE telecom_tower_summary SET
risk_points =
    (CASE WHEN avg_uptime_percentage < 89.44 THEN 1 ELSE 0 END) +
    (CASE WHEN total_downtime_minutes > 202.32 THEN 1 ELSE 0 END) +
    (CASE WHEN total_users_affected > 410 THEN 1 ELSE 0 END) +
    (CASE WHEN repeat_outage_indicator = 1 THEN 1 ELSE 0 END);

UPDATE telecom_tower_summary SET
site_risk_category_preliminary = CASE
    WHEN risk_points = 0 THEN 'Low Risk'
    WHEN risk_points = 1 THEN 'Medium Risk'
    WHEN risk_points = 2 THEN 'High Risk'
    ELSE 'Critical Risk'   -- risk_points 3 or 4
END;

-- Validation: distribution
SELECT site_risk_category_preliminary, COUNT(*), ROUND(100.0*COUNT(*)/70599,1) AS pct
FROM telecom_tower_summary
GROUP BY 1
ORDER BY 2 DESC;

-- Cross-check: do towers with multiple operators skew toward higher/lower
-- risk vs single-operator towers? (transparency check on the attribute
-- instability finding's effect on risk labeling)
SELECT
    CASE WHEN distinct_operator_count > 1 THEN 'Multi-operator tower' ELSE 'Single-operator tower' END AS tower_type,
    site_risk_category_preliminary,
    COUNT(*) AS n
FROM telecom_tower_summary
GROUP BY 1,2
ORDER BY 1,2;

-- Join repeat_outage_indicator and site_risk_category_preliminary back
-- onto the row-level feature table (each row inherits its tower's values)
ALTER TABLE telecom_outage_features
    ADD COLUMN repeat_outage_indicator INT,
    ADD COLUMN site_risk_category_preliminary TEXT;

UPDATE telecom_outage_features f
SET repeat_outage_indicator = s.repeat_outage_indicator,
    site_risk_category_preliminary = s.site_risk_category_preliminary
FROM telecom_tower_summary s
WHERE f.tower_id = s.tower_id;

-- Final null check on the join
SELECT
    COUNT(*) FILTER (WHERE repeat_outage_indicator IS NULL) AS null_repeat_flag,
    COUNT(*) FILTER (WHERE site_risk_category_preliminary IS NULL) AS null_risk_cat
FROM telecom_outage_features;

-- Row count reconciliation across the whole feature-engineering phase
SELECT
    (SELECT COUNT(*) FROM telecom_outage_raw) AS raw_rows,
    (SELECT COUNT(*) FROM telecom_outage_clean) AS clean_rows,
    (SELECT COUNT(*) FROM telecom_outage_features) AS feature_rows,
    (SELECT COUNT(*) FROM telecom_tower_summary) AS tower_summary_rows,
    (SELECT COUNT(DISTINCT tower_id) FROM telecom_outage_clean) AS distinct_towers;


-- ================================================================
-- FILE: 11_network_overview.sql
-- ================================================================
-- =====================================================================
-- NETWORK OVERVIEW
-- Grain note: telecom_outage_features has 100,000 rows = 100,000
-- observations across 70,599 unique towers (not a 1:1 tower:row map -
-- see Step 1/7 documentation). All "total" metrics below are sums
-- across observations; "per tower" metrics divide by unique tower count.
-- =====================================================================

SELECT
    COUNT(DISTINCT tower_id)                          AS unique_towers,
    COUNT(*)                                          AS total_observations,
    SUM(outage_count)                                 AS total_outages,
    ROUND(SUM(downtime_minutes)::numeric, 1)          AS total_downtime_minutes,
    ROUND(AVG(uptime_percentage)::numeric, 2)         AS avg_uptime_pct,
    ROUND(AVG(downtime_minutes)::numeric, 2)          AS avg_downtime_minutes,
    ROUND(AVG(outage_count)::numeric, 2)              AS avg_outage_count,
    SUM(avg_users_affected)                           AS total_users_affected,
    ROUND(AVG(avg_users_affected)::numeric, 1)         AS avg_users_affected_per_obs,
    COUNT(*) FILTER (WHERE avg_users_affected > 0)    AS outage_affected_observations,
    ROUND(100.0 * COUNT(*) FILTER (WHERE avg_users_affected > 0) / COUNT(*), 2) AS pct_obs_with_impact
FROM telecom_outage_features;

-- Per-tower normalized view (using telecom_tower_summary to avoid the
-- observation-count bias flagged in Phase 3)
SELECT
    COUNT(*)                                              AS towers,
    ROUND(AVG(avg_uptime_percentage)::numeric, 2)         AS avg_tower_uptime_pct,
    ROUND(AVG(total_downtime_minutes / total_observations)::numeric, 2) AS avg_downtime_per_observation,
    ROUND(AVG(total_outage_count::numeric / total_observations)::numeric, 2) AS avg_outage_count_per_observation,
    SUM(CASE WHEN repeat_outage_indicator = 1 THEN 1 ELSE 0 END) AS repeat_outage_towers,
    ROUND(100.0 * SUM(CASE WHEN repeat_outage_indicator = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_repeat_outage_towers
FROM telecom_tower_summary;

-- High-risk / critical-risk tower counts (preliminary categorization from Phase 3)
SELECT site_risk_category_preliminary, COUNT(*) AS towers,
       ROUND(100.0*COUNT(*)/(SELECT COUNT(*) FROM telecom_tower_summary),1) AS pct
FROM telecom_tower_summary
GROUP BY 1
ORDER BY 2 DESC;


-- ================================================================
-- FILE: 12_operator_analysis.sql
-- ================================================================
-- =====================================================================
-- OPERATOR ANALYSIS
-- Grain note: `operator` is recorded per-observation, not stably per
-- physical tower (see Phase 3 tower-instability finding: 25.8% of
-- towers show multiple operators across their observations). This
-- analysis therefore compares operators AT THE OBSERVATION LEVEL - i.e.
-- "how reliable were readings logged under Operator X" - not "how
-- reliable is Operator X's fixed network of towers", since this
-- dataset does not support a stable operator-to-tower mapping.
-- =====================================================================

SELECT
    operator,
    COUNT(*)                                         AS observations,
    COUNT(DISTINCT tower_id)                         AS distinct_towers_seen,
    ROUND(AVG(uptime_percentage)::numeric, 2)        AS avg_uptime_pct,
    ROUND(AVG(downtime_minutes)::numeric, 2)         AS avg_downtime_minutes,
    SUM(downtime_minutes)::numeric(12,1)             AS total_downtime_minutes,
    ROUND(AVG(outage_count)::numeric, 2)             AS avg_outage_count,
    SUM(outage_count)                                AS total_outages,
    ROUND(AVG(avg_users_affected)::numeric, 1)       AS avg_users_affected,
    SUM(avg_users_affected)                          AS total_users_affected,
    COUNT(*) FILTER (WHERE avg_users_affected > 0)   AS impactful_observations,
    ROUND(100.0*COUNT(*) FILTER (WHERE avg_users_affected > 0)/COUNT(*), 2) AS pct_impactful
FROM telecom_outage_features
GROUP BY operator
ORDER BY avg_uptime_pct DESC;

-- Operator x outage_reason (root causes by operator, among impactful observations)
SELECT operator, outage_reason, COUNT(*) AS n
FROM telecom_outage_features
WHERE outage_reason IS NOT NULL
GROUP BY operator, outage_reason
ORDER BY operator, n DESC;

-- Operator x outage_severity distribution
SELECT operator, outage_severity, COUNT(*) AS n
FROM telecom_outage_features
GROUP BY operator, outage_severity
ORDER BY operator,
    CASE outage_severity WHEN 'High' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END;

-- Statistical context check: is the uptime difference across operators
-- large relative to natural spread, or trivial? (range of operator
-- averages vs. overall standard deviation of individual observations)
WITH op_avgs AS (
    SELECT operator, AVG(uptime_percentage) AS op_avg FROM telecom_outage_features GROUP BY operator
)
SELECT
    (SELECT ROUND((MAX(op_avg) - MIN(op_avg))::numeric, 3) FROM op_avgs) AS range_of_operator_avg_uptime,
    (SELECT ROUND(STDDEV(uptime_percentage)::numeric, 3) FROM telecom_outage_features) AS overall_uptime_stddev;


-- ================================================================
-- FILE: 13_geographic_analysis.sql
-- ================================================================
-- =====================================================================
-- GEOGRAPHIC ANALYSIS
-- Grain note: per Phase 2 finding, `city` and `state` are independent,
-- non-hierarchical dimensions in this dataset (every city pairs with
-- all 37 states). They are analyzed here as two SEPARATE geographic
-- cuts, not as a nested "State -> City" drill-down.
-- =====================================================================

-- States with the highest outage frequency
SELECT state,
       COUNT(*) AS observations,
       SUM(outage_count) AS total_outages,
       ROUND(AVG(outage_count)::numeric,2) AS avg_outage_count,
       ROUND(SUM(downtime_minutes)::numeric,1) AS total_downtime_minutes,
       ROUND(AVG(uptime_percentage)::numeric,2) AS avg_uptime_pct
FROM telecom_outage_features
GROUP BY state
ORDER BY total_outages DESC
LIMIT 10;

-- States with the greatest downtime
SELECT state, ROUND(SUM(downtime_minutes)::numeric,1) AS total_downtime_minutes
FROM telecom_outage_features
GROUP BY state
ORDER BY total_downtime_minutes DESC
LIMIT 10;

-- Statistical context: range of state avg uptime vs overall stddev (same
-- sanity check as operator analysis, to avoid overstating geographic effects)
WITH state_avgs AS (
    SELECT state, AVG(uptime_percentage) AS st_avg FROM telecom_outage_features GROUP BY state
)
SELECT
    (SELECT ROUND((MAX(st_avg)-MIN(st_avg))::numeric,3) FROM state_avgs) AS range_of_state_avg_uptime,
    (SELECT ROUND(STDDEV(uptime_percentage)::numeric,3) FROM telecom_outage_features) AS overall_uptime_stddev;

-- Cities with poor reliability (lowest avg uptime)
SELECT city,
       COUNT(*) AS observations,
       ROUND(AVG(uptime_percentage)::numeric,2) AS avg_uptime_pct,
       ROUND(SUM(downtime_minutes)::numeric,1) AS total_downtime_minutes,
       SUM(outage_count) AS total_outages,
       SUM(avg_users_affected) AS total_users_affected
FROM telecom_outage_features
GROUP BY city
ORDER BY avg_uptime_pct ASC
LIMIT 15;

-- Statistical context for city-level uptime variation
WITH city_avgs AS (
    SELECT city, AVG(uptime_percentage) AS ct_avg FROM telecom_outage_features GROUP BY city
)
SELECT
    (SELECT ROUND((MAX(ct_avg)-MIN(ct_avg))::numeric,3) FROM city_avgs) AS range_of_city_avg_uptime,
    (SELECT ROUND(STDDEV(uptime_percentage)::numeric,3) FROM telecom_outage_features) AS overall_uptime_stddev;

-- Towers with repeated outages (top 15, using tower_summary - already
-- computed correctly at tower grain)
SELECT tower_id, city, mode_operator, total_observations,
       impactful_outage_observations, repeat_outage_indicator,
       avg_uptime_percentage, total_downtime_minutes, total_users_affected
FROM telecom_tower_summary
WHERE repeat_outage_indicator = 1
ORDER BY impactful_outage_observations DESC, total_downtime_minutes DESC
LIMIT 15;

-- Towers with the lowest uptime (tower-level average, min 1 observation)
SELECT tower_id, city, mode_operator, total_observations,
       avg_uptime_percentage, total_downtime_minutes, total_users_affected
FROM telecom_tower_summary
ORDER BY avg_uptime_percentage ASC
LIMIT 15;

-- Locations (city) with the highest customer impact
SELECT city,
       SUM(total_users_affected) AS total_users_affected,
       COUNT(*) AS towers,
       ROUND(SUM(total_users_affected)::numeric / COUNT(*), 1) AS avg_users_affected_per_tower
FROM telecom_tower_summary
GROUP BY city
ORDER BY total_users_affected DESC
LIMIT 10;


-- ================================================================
-- FILE: 14_root_cause_analysis.sql
-- ================================================================
-- =====================================================================
-- ROOT-CAUSE ANALYSIS (outage_reason)
-- Reminder from Phase 1/3 findings: outage_reason is NULL exactly when
-- avg_users_affected = 0 (perfect 1:1 relationship, no exceptions).
-- All queries below therefore operate on the 66,654 observations where
-- outage_reason IS NOT NULL (i.e. a user-impacting event was recorded).
-- Also recall: outage_count is only weakly correlated (r ~ 0.15) with
-- downtime/reason, so outage_count is NOT used here as the impact
-- signal - avg_users_affected / outage_reason are used instead, since
-- those two are internally consistent with each other.
-- =====================================================================

-- Most frequent outage causes
SELECT outage_reason, COUNT(*) AS n,
       ROUND(100.0*COUNT(*)/(SELECT COUNT(*) FROM telecom_outage_features WHERE outage_reason IS NOT NULL),2) AS pct_of_impactful_obs
FROM telecom_outage_features
WHERE outage_reason IS NOT NULL
GROUP BY outage_reason
ORDER BY n DESC;

-- Causes responsible for the greatest downtime
SELECT outage_reason,
       ROUND(SUM(downtime_minutes)::numeric,1) AS total_downtime_minutes,
       ROUND(AVG(downtime_minutes)::numeric,2) AS avg_downtime_minutes
FROM telecom_outage_features
WHERE outage_reason IS NOT NULL
GROUP BY outage_reason
ORDER BY total_downtime_minutes DESC;

-- Causes affecting the most users
SELECT outage_reason,
       SUM(avg_users_affected) AS total_users_affected,
       ROUND(AVG(avg_users_affected)::numeric,1) AS avg_users_affected
FROM telecom_outage_features
WHERE outage_reason IS NOT NULL
GROUP BY outage_reason
ORDER BY total_users_affected DESC;

-- Causes associated with lowest uptime
SELECT outage_reason,
       ROUND(AVG(uptime_percentage)::numeric,2) AS avg_uptime_pct,
       COUNT(*) AS n
FROM telecom_outage_features
WHERE outage_reason IS NOT NULL
GROUP BY outage_reason
ORDER BY avg_uptime_pct ASC;

-- Statistical context: is the spread across causes meaningful?
WITH cause_avgs AS (
    SELECT outage_reason, AVG(downtime_minutes) AS avg_dt
    FROM telecom_outage_features WHERE outage_reason IS NOT NULL
    GROUP BY outage_reason
)
SELECT
    (SELECT ROUND((MAX(avg_dt)-MIN(avg_dt))::numeric,2) FROM cause_avgs) AS range_of_cause_avg_downtime,
    (SELECT ROUND(STDDEV(downtime_minutes)::numeric,2) FROM telecom_outage_features WHERE outage_reason IS NOT NULL) AS overall_downtime_stddev;

-- Recurring outage causes: towers where the SAME cause appears more than
-- once across their observations
SELECT outage_reason, COUNT(*) AS tower_occurrences
FROM (
    SELECT tower_id, outage_reason, COUNT(*) AS n
    FROM telecom_outage_features
    WHERE outage_reason IS NOT NULL
    GROUP BY tower_id, outage_reason
    HAVING COUNT(*) > 1
) t
GROUP BY outage_reason
ORDER BY tower_occurrences DESC;

-- outage_severity distribution by cause
SELECT outage_reason, outage_severity, COUNT(*) AS n
FROM telecom_outage_features
WHERE outage_reason IS NOT NULL
GROUP BY outage_reason, outage_severity
ORDER BY outage_reason,
    CASE outage_severity WHEN 'High' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END;


-- ================================================================
-- FILE: 15_network_technology_analysis.sql
-- ================================================================
-- =====================================================================
-- NETWORK TECHNOLOGY ANALYSIS (2G/3G/4G/5G)
-- Reminder: network_type is recorded per-observation, and 18.2% of
-- towers show more than one network_type across their observations
-- (Phase 3 finding) - so this is an observation-level comparison, not
-- a claim about a fixed technology per physical site.
-- =====================================================================

SELECT
    network_type,
    COUNT(*) AS observations,
    ROUND(AVG(uptime_percentage)::numeric,2) AS avg_uptime_pct,
    ROUND(AVG(downtime_minutes)::numeric,2) AS avg_downtime_minutes,
    ROUND(AVG(outage_count)::numeric,2) AS avg_outage_count,
    ROUND(AVG(avg_users_affected)::numeric,1) AS avg_users_affected,
    COUNT(*) FILTER (WHERE outage_reason IS NOT NULL) AS impactful_observations,
    ROUND(100.0*COUNT(*) FILTER (WHERE outage_reason IS NOT NULL)/COUNT(*),2) AS pct_impactful
FROM telecom_outage_features
GROUP BY network_type
ORDER BY avg_uptime_pct DESC;

-- Statistical context
WITH net_avgs AS (
    SELECT network_type, AVG(uptime_percentage) AS avg_up FROM telecom_outage_features GROUP BY network_type
)
SELECT
    (SELECT ROUND((MAX(avg_up)-MIN(avg_up))::numeric,3) FROM net_avgs) AS range_of_network_avg_uptime,
    (SELECT ROUND(STDDEV(uptime_percentage)::numeric,3) FROM telecom_outage_features) AS overall_uptime_stddev;

-- Network type x outage_reason
SELECT network_type, outage_reason, COUNT(*) AS n
FROM telecom_outage_features
WHERE outage_reason IS NOT NULL
GROUP BY network_type, outage_reason
ORDER BY network_type, n DESC;


-- ================================================================
-- FILE: 16_time_analysis.sql
-- ================================================================
-- =====================================================================
-- TIME ANALYSIS
-- Reminder: data spans 2025-09-01 to 2025-10-01 (31 days, effectively
-- one month + 1 day of the next). Monthly/quarterly trend claims are
-- NOT supportable with this data - there is no second month to compare
-- against. Daily and day-of-week patterns ARE supportable, so this
-- analysis focuses there.
-- =====================================================================

-- Daily trend: outages, downtime, uptime by calendar date
SELECT obs_date,
       COUNT(*) AS observations,
       SUM(outage_count) AS total_outages,
       ROUND(SUM(downtime_minutes)::numeric,1) AS total_downtime_minutes,
       ROUND(AVG(uptime_percentage)::numeric,2) AS avg_uptime_pct
FROM telecom_outage_features
GROUP BY obs_date
ORDER BY obs_date;

-- Statistical context: is there a real daily trend or just noise around a
-- flat mean? Compare day-to-day range vs stddev of daily averages
WITH daily AS (
    SELECT obs_date, AVG(uptime_percentage) AS daily_avg_uptime
    FROM telecom_outage_features GROUP BY obs_date
)
SELECT
    ROUND((MAX(daily_avg_uptime)-MIN(daily_avg_uptime))::numeric,3) AS range_of_daily_avg_uptime,
    ROUND(STDDEV(daily_avg_uptime)::numeric,4) AS stddev_of_daily_avgs
FROM daily;

-- Day-of-week pattern
SELECT obs_day_of_week_name, obs_day_of_week_number, is_weekend,
       COUNT(*) AS observations,
       ROUND(AVG(uptime_percentage)::numeric,2) AS avg_uptime_pct,
       ROUND(AVG(downtime_minutes)::numeric,2) AS avg_downtime_minutes,
       ROUND(AVG(outage_count)::numeric,2) AS avg_outage_count
FROM telecom_outage_features
GROUP BY 1,2,3
ORDER BY obs_day_of_week_number;

-- Weekday vs weekend comparison
SELECT is_weekend,
       COUNT(*) AS observations,
       ROUND(AVG(uptime_percentage)::numeric,2) AS avg_uptime_pct,
       ROUND(AVG(downtime_minutes)::numeric,2) AS avg_downtime_minutes,
       ROUND(AVG(outage_count)::numeric,2) AS avg_outage_count
FROM telecom_outage_features
GROUP BY is_weekend;

-- Weekly trend (ISO week number)
SELECT obs_week_number,
       MIN(obs_date) AS week_start, MAX(obs_date) AS week_end,
       COUNT(*) AS observations,
       SUM(outage_count) AS total_outages,
       ROUND(SUM(downtime_minutes)::numeric,1) AS total_downtime_minutes,
       ROUND(AVG(uptime_percentage)::numeric,2) AS avg_uptime_pct
FROM telecom_outage_features
GROUP BY obs_week_number
ORDER BY obs_week_number;

-- Monthly view (included per blueprint request, but flagged: only 2 partial
-- calendar months exist, so this is NOT a trend - just a two-point comparison
-- confounded by very unequal day counts: 30 days of Sept vs 1 day of Oct)
SELECT obs_year, obs_month_name, COUNT(*) AS observations,
       SUM(outage_count) AS total_outages,
       ROUND(SUM(downtime_minutes)::numeric,1) AS total_downtime_minutes,
       ROUND(AVG(uptime_percentage)::numeric,2) AS avg_uptime_pct
FROM telecom_outage_features
GROUP BY obs_year, obs_month_name, obs_month_number
ORDER BY obs_month_number;


-- ================================================================
-- EXPORTS: these were originally run as one-off \COPY commands and
-- are restored here so the SQL pipeline actually hands off the CSVs
-- the Python pipeline (Python Outage EDA Modeling.py) depends on.
-- Creates ./data/ relative to wherever psql is run from if it doesn't
-- already exist -- run `mkdir -p data` first if needed.
-- ================================================================
\COPY telecom_outage_clean TO 'data/telecom_outage_clean.csv' WITH CSV HEADER;
\COPY (
SELECT row_id, tower_id, obs_date, operator, city, state, uptime_percentage,
       downtime_minutes, outage_count, outage_reason, network_type,
       avg_users_affected, outage_severity, reliability_status, high_risk_flag,
       downtime_hours, observation_month, day_of_week
FROM telecom_outage_features ORDER BY row_id
) TO 'data/telecom_outage_features.csv' WITH CSV HEADER;
\COPY telecom_tower_summary TO 'data/telecom_tower_summary.csv' WITH CSV HEADER;

-- Final row-count reconciliation (should read 100000 / 100000 / 100000 / 70599)
SELECT
    (SELECT COUNT(*) FROM telecom_outage_raw)      AS raw_rows,
    (SELECT COUNT(*) FROM telecom_outage_clean)    AS clean_rows,
    (SELECT COUNT(*) FROM telecom_outage_features) AS feature_rows,
    (SELECT COUNT(*) FROM telecom_tower_summary)   AS tower_summary_rows;
