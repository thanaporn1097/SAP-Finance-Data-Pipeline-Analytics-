-- 04_create_dwh_dim_table.sql
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
-- ============================================================
-- dim_company
DROP TABLE IF EXISTS dwh.dim_company;
GO

CREATE TABLE dwh.dim_company (
    company_key   INT            IDENTITY(1,1) NOT NULL,
    company_code  NVARCHAR(10)   NOT NULL,
    company_name  NVARCHAR(100)  NULL,
    is_active     BIT            NOT NULL CONSTRAINT DF_dim_company_is_active  DEFAULT (1),
    created_at    DATETIME2(0)   NOT NULL CONSTRAINT DF_dim_company_created_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_dim_company PRIMARY KEY (company_key),
    CONSTRAINT UQ_dim_company_code UNIQUE (company_code)
);
GO
-- RESEED to -1 first so that next auto-identity = 0 is used for INSERT,
-- then after key=0 is inserted, next auto-identity becomes 1 automatically.
DBCC CHECKIDENT ('dwh.dim_company', RESEED, -1);
GO

SET IDENTITY_INSERT dwh.dim_company ON;
INSERT INTO dwh.dim_company (company_key, company_code, company_name, is_active)
VALUES (0, N'UNKNOWN', N'Unknown Company', 1);
SET IDENTITY_INSERT dwh.dim_company OFF;
GO

;WITH company_base AS (
    SELECT DISTINCT
        NULLIF(TRIM(b.bukrs), '')           AS company_code,
        UPPER(NULLIF(TRIM(t.butxt), ''))    AS company_name
    FROM stg.stg_bkpf b
    LEFT JOIN stg.stg_t001 t
        ON NULLIF(TRIM(b.bukrs), '') = NULLIF(TRIM(t.bukrs), '')
    WHERE NULLIF(TRIM(b.bukrs), '') IS NOT NULL
)
INSERT INTO dwh.dim_company (company_code, company_name, is_active)
SELECT
    company_code,
    company_name,
    CAST(1 AS BIT)
FROM company_base;
GO

-- ============================================================
-- dim_customer
DROP TABLE IF EXISTS dwh.dim_customer;
GO

CREATE TABLE dwh.dim_customer (
    customer_key   INT             IDENTITY(1,1) NOT NULL,
    customer_code  NVARCHAR(20)    NOT NULL,
    customer_name  NVARCHAR(255)   NULL,
    country_code   NVARCHAR(10)    NULL,
    region         NVARCHAR(50)    NULL,
    city           NVARCHAR(100)   NULL,
    industry       NVARCHAR(50)    NULL,
    account_group  NVARCHAR(50)    NULL,
    customer_type  NVARCHAR(50)    NULL,
    is_active      BIT             NOT NULL CONSTRAINT DF_dim_customer_is_active  DEFAULT (1),
    created_at     DATETIME2(0)    NOT NULL CONSTRAINT DF_dim_customer_created_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_dim_customer PRIMARY KEY (customer_key),
    CONSTRAINT UQ_dim_customer_code UNIQUE (customer_code)
);
GO

DBCC CHECKIDENT ('dwh.dim_customer', RESEED, -1);
GO

SET IDENTITY_INSERT dwh.dim_customer ON;
INSERT INTO dwh.dim_customer
    (customer_key, customer_code, customer_name, account_group, customer_type, is_active)
VALUES (0, N'UNKNOWN', N'Unknown Customer', NULL, NULL, 1);
SET IDENTITY_INSERT dwh.dim_customer OFF;
GO

;WITH customer_source AS (
    SELECT
        NULLIF(TRIM(kunnr), '')       AS customer_code,
        MAX(NULLIF(TRIM(name1), ''))  AS customer_name,
        MAX(NULLIF(TRIM(land1), ''))  AS country_code,
        MAX(NULLIF(TRIM(regio), ''))  AS region,
        MAX(NULLIF(TRIM(ort01), ''))  AS city,
        MAX(NULLIF(TRIM(brsch), ''))  AS industry,
        MAX(NULLIF(TRIM(ktokd), ''))  AS account_group
    FROM stg.stg_kna1
    GROUP BY NULLIF(TRIM(kunnr), '')
)
INSERT INTO dwh.dim_customer
    (customer_code, customer_name, country_code, region, city,
     industry, account_group, customer_type, is_active)
SELECT
    customer_code,
    customer_name,
    country_code,
    region,
    city,
    industry,
    account_group,
    account_group AS customer_type,
    1
FROM customer_source
WHERE customer_code IS NOT NULL;
GO

-- ============================================================
-- dim_date
DROP TABLE IF EXISTS dwh.dim_date;
GO

CREATE TABLE dwh.dim_date (
    date_key          INT            NOT NULL,
    full_date         DATE           NOT NULL,
    calendar_year     INT            NOT NULL,
    quarter_no        TINYINT        NOT NULL,
    quarter_name      NVARCHAR(10)   NOT NULL,
    month_no          TINYINT        NOT NULL,
    month_name        NVARCHAR(20)   NOT NULL,
    month_short       NVARCHAR(3)    NOT NULL,
    month_key         INT            NOT NULL,
    year_month_label  NVARCHAR(20)   NOT NULL,
    year_month_sort   INT            NOT NULL,
    month_start_date  DATE           NOT NULL,
    month_end_date    DATE           NOT NULL,
    day_of_month      TINYINT        NOT NULL,
    day_of_week_no    TINYINT        NOT NULL,
    day_of_week_name  NVARCHAR(20)   NOT NULL,
    is_month_end      BIT            NOT NULL,
    is_weekend        BIT            NOT NULL,
    CONSTRAINT PK_dim_date PRIMARY KEY (date_key),
    CONSTRAINT UQ_dim_date_full_date UNIQUE (full_date)
);
GO

-- Default row for unresolved dates
INSERT INTO dwh.dim_date VALUES (
    0, CAST('1900-01-01' AS DATE),
    0, 0, N'Unknown', 0, N'Unknown', N'UNK',
    0, N'Unknown', 0,
    CAST('1900-01-01' AS DATE), CAST('1900-01-01' AS DATE),
    0, 0, N'Unknown', 0, 0
);
GO

DECLARE @min_source_date DATE;
DECLARE @max_source_date DATE;
DECLARE @start_date      DATE;
DECLARE @end_date        DATE;

;WITH source_dates AS (
    SELECT COALESCE(
               TRY_CONVERT(DATE, NULLIF(TRIM(bldat), ''), 112),
               TRY_CONVERT(DATE, NULLIF(TRIM(bldat), ''), 23),
               TRY_CONVERT(DATE, NULLIF(TRIM(bldat), ''), 120),
               TRY_CONVERT(DATE, NULLIF(TRIM(bldat), ''))
           ) AS dt
    FROM stg.stg_bkpf
    UNION ALL
    SELECT COALESCE(
               TRY_CONVERT(DATE, NULLIF(TRIM(budat), ''), 112),
               TRY_CONVERT(DATE, NULLIF(TRIM(budat), ''), 23),
               TRY_CONVERT(DATE, NULLIF(TRIM(budat), ''), 120),
               TRY_CONVERT(DATE, NULLIF(TRIM(budat), ''))
           ) AS dt
    FROM stg.stg_bkpf
)
SELECT
    @min_source_date = MIN(dt),
    @max_source_date = MAX(dt)
FROM source_dates
WHERE dt IS NOT NULL
  AND dt >= CAST('1990-01-01' AS DATE)
  AND dt <  CAST('2100-01-01' AS DATE);

SET @start_date = ISNULL(
    DATEFROMPARTS(YEAR(DATEADD(MONTH, -1, @min_source_date)),
                  MONTH(DATEADD(MONTH, -1, @min_source_date)), 1),
    CAST('2022-01-01' AS DATE)
);
SET @end_date = ISNULL(
    EOMONTH(DATEADD(MONTH, 1, @max_source_date)),
    CAST('2025-12-31' AS DATE)
);

;WITH d AS (
    SELECT @start_date AS full_date
    UNION ALL
    SELECT DATEADD(DAY, 1, full_date)
    FROM d
    WHERE full_date < @end_date
)
INSERT INTO dwh.dim_date (
    date_key, full_date, calendar_year, quarter_no, quarter_name,
    month_no, month_name, month_short, month_key, year_month_label,
    year_month_sort, month_start_date, month_end_date,
    day_of_month, day_of_week_no, day_of_week_name, is_month_end, is_weekend
)
SELECT
    CAST(CONVERT(CHAR(8), full_date, 112) AS INT)                                        AS date_key,
    full_date,
    YEAR(full_date)                                                                      AS calendar_year,
    DATEPART(QUARTER, full_date)                                                         AS quarter_no,
    CONCAT(N'Q', DATEPART(QUARTER, full_date))                                           AS quarter_name,
    MONTH(full_date)                                                                     AS month_no,
    DATENAME(MONTH, full_date)                                                           AS month_name,
    LEFT(DATENAME(MONTH, full_date), 3)                                                  AS month_short,
    YEAR(full_date) * 100 + MONTH(full_date)                                             AS month_key,
    CONCAT(LEFT(DATENAME(MONTH, full_date), 3), N' ', YEAR(full_date))                   AS year_month_label,
    YEAR(full_date) * 100 + MONTH(full_date)                                             AS year_month_sort,
    DATEFROMPARTS(YEAR(full_date), MONTH(full_date), 1)                                  AS month_start_date,
    EOMONTH(full_date)                                                                   AS month_end_date,
    DAY(full_date)                                                                       AS day_of_month,
    DATEPART(WEEKDAY, full_date)                                                         AS day_of_week_no,
    DATENAME(WEEKDAY, full_date)                                                         AS day_of_week_name,
    CASE WHEN full_date = EOMONTH(full_date) THEN 1 ELSE 0 END                           AS is_month_end,
    CASE WHEN DATENAME(WEEKDAY, full_date) IN (N'Saturday', N'Sunday') THEN 1 ELSE 0 END AS is_weekend
FROM d
OPTION (MAXRECURSION 0);
GO

CREATE INDEX IX_dim_date_month_key      ON dwh.dim_date (month_key);
CREATE INDEX IX_dim_date_year_month_sort ON dwh.dim_date (year_month_sort);
GO

-- ============================================================
-- dim_month (derived from dim_date)
DROP TABLE IF EXISTS dwh.dim_month;
GO

CREATE TABLE dwh.dim_month (
    month_key        INT            NOT NULL,
    month_start_date DATE           NOT NULL,
    month_end_date   DATE           NOT NULL,
    calendar_year    INT            NOT NULL,
    quarter_no       INT            NOT NULL,
    quarter_name     NVARCHAR(10)   NOT NULL,
    month_no         INT            NOT NULL,
    month_name       NVARCHAR(20)   NOT NULL,
    month_short      NVARCHAR(5)    NOT NULL,
    month_sort       INT            NOT NULL,
    year_month_label NVARCHAR(20)   NOT NULL,
    created_at       DATETIME2(0)   NOT NULL CONSTRAINT DF_dim_month_created_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_dim_month PRIMARY KEY (month_key)
);
GO

INSERT INTO dwh.dim_month (
    month_key, month_start_date, month_end_date, calendar_year,
    quarter_no, quarter_name, month_no, month_name, month_short,
    month_sort, year_month_label
)
SELECT DISTINCT
    month_key,
    month_start_date,
    month_end_date,
    calendar_year,
    quarter_no,
    quarter_name,
    month_no,
    month_name,
    month_short,
    (calendar_year * 100 + month_no) AS month_sort,
    year_month_label
FROM dwh.dim_date
WHERE date_key <> 0;
GO

-- ============================================================
-- dim_profit_center
DROP TABLE IF EXISTS dwh.dim_profit_center;
GO

CREATE TABLE dwh.dim_profit_center (
    prctr_key                INT             IDENTITY(1,1) NOT NULL,
    profit_center_code       NVARCHAR(20)    NOT NULL,
    controlling_area         NVARCHAR(10)    NULL,
    profit_center_name       NVARCHAR(255)   NULL,
    profit_center_short_name NVARCHAR(100)   NULL,
    company_code             NVARCHAR(10)    NULL,
    department               NVARCHAR(100)   NULL,
    responsible_person       NVARCHAR(100)   NULL,
    profit_center_group      NVARCHAR(100)   NULL,
    segment                  NVARCHAR(100)   NULL,
    currency_code            NVARCHAR(10)    NULL,
    country_code             NVARCHAR(10)    NULL,
    region                   NVARCHAR(50)    NULL,
    valid_to_date            DATE            NULL,
    language_code            NVARCHAR(10)    NULL,
    is_locked                BIT             NOT NULL CONSTRAINT DF_dim_profit_center_is_locked  DEFAULT (0),
    is_active                BIT             NOT NULL CONSTRAINT DF_dim_profit_center_is_active  DEFAULT (1),
    created_at               DATETIME2(0)    NOT NULL CONSTRAINT DF_dim_profit_center_created_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_dim_profit_center PRIMARY KEY (prctr_key),
    CONSTRAINT UQ_dim_profit_center_code_kokrs UNIQUE (profit_center_code, controlling_area)
);
GO

DBCC CHECKIDENT ('dwh.dim_profit_center', RESEED, -1);
GO

SET IDENTITY_INSERT dwh.dim_profit_center ON;
INSERT INTO dwh.dim_profit_center (
    prctr_key, profit_center_code, controlling_area, profit_center_name,
    profit_center_short_name, company_code, department, responsible_person,
    profit_center_group, segment, currency_code, country_code, region,
    valid_to_date, language_code, is_locked, is_active
)
VALUES (
    0, N'UNKNOWN', NULL, N'Unknown Profit Center', N'Unknown Profit Center',
    NULL, N'Unknown', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, 1
);
SET IDENTITY_INSERT dwh.dim_profit_center OFF;
GO

;WITH cepc_clean AS (
    SELECT
        CASE
            WHEN TRY_CAST(NULLIF(TRIM(prctr), '') AS BIGINT) IS NOT NULL
                THEN CAST(TRY_CAST(NULLIF(TRIM(prctr), '') AS BIGINT) AS NVARCHAR(20))
            ELSE NULLIF(TRIM(prctr), '')
        END AS profit_center_code,
        NULLIF(TRIM(kokrs), '') AS controlling_area,
        NULLIF(TRIM(bukrs), '') AS company_code,
        NULLIF(TRIM(abtei), '') AS department,
        NULLIF(TRIM(verak), '') AS responsible_person,
        NULLIF(TRIM(khinr), '') AS profit_center_group,
        NULLIF(TRIM(segment), '') AS segment,
        NULLIF(TRIM(waers), '') AS currency_code,
        NULLIF(TRIM(land1), '') AS country_code,
        NULLIF(TRIM(regio), '') AS region,
        COALESCE(
            TRY_CONVERT(DATE, NULLIF(TRIM(datbi), ''), 112),
            TRY_CONVERT(DATE, NULLIF(TRIM(datbi), ''), 23),
            TRY_CONVERT(DATE, NULLIF(TRIM(datbi), ''), 120),
            TRY_CONVERT(DATE, NULLIF(TRIM(datbi), ''))
        ) AS valid_to_date,
        CASE
            WHEN UPPER(NULLIF(TRIM(lock_ind), '')) IN (N'X', N'1', N'Y', N'YES', N'TRUE', N'LOCKED')
                THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT)
        END AS is_locked,
        CASE
            WHEN UPPER(NULLIF(TRIM(is_deleted), '')) IN (N'X', N'1', N'Y', N'YES', N'TRUE') THEN 1
            ELSE 0
        END AS is_deleted_flag,
        load_timestamp,
        source_file_name,
        ROW_NUMBER() OVER (
            PARTITION BY
                CASE WHEN TRY_CAST(NULLIF(TRIM(prctr), '') AS BIGINT) IS NOT NULL
                     THEN CAST(TRY_CAST(NULLIF(TRIM(prctr), '') AS BIGINT) AS NVARCHAR(20))
                     ELSE NULLIF(TRIM(prctr), '') END,
                NULLIF(TRIM(kokrs), '')
            ORDER BY
                CASE WHEN UPPER(NULLIF(TRIM(is_deleted), '')) IN
                         (N'X', N'1', N'Y', N'YES', N'TRUE') THEN 2 ELSE 1 END,
                COALESCE(
                    TRY_CONVERT(DATE, NULLIF(TRIM(datbi), ''), 112),
                    TRY_CONVERT(DATE, NULLIF(TRIM(datbi), ''), 23),
                    TRY_CONVERT(DATE, NULLIF(TRIM(datbi), ''), 120),
                    TRY_CONVERT(DATE, NULLIF(TRIM(datbi), ''))
                ) DESC,
                load_timestamp DESC
        ) AS rn
    FROM stg.stg_cepc
    WHERE NULLIF(TRIM(prctr), '') IS NOT NULL
),
cepc_best AS (
    SELECT
        profit_center_code, controlling_area, company_code, department,
        responsible_person, profit_center_group, segment, currency_code,
        country_code, region, valid_to_date, is_locked,
        CAST(CASE WHEN is_deleted_flag = 1 OR is_locked = 1 THEN 0 ELSE 1 END AS BIT) AS is_active
    FROM cepc_clean
    WHERE rn = 1
      AND profit_center_code IS NOT NULL
),
cepct_clean AS (
    SELECT
        CASE
            WHEN TRY_CAST(NULLIF(TRIM(prctr), '') AS BIGINT) IS NOT NULL
                THEN CAST(TRY_CAST(NULLIF(TRIM(prctr), '') AS BIGINT) AS NVARCHAR(20))
            ELSE NULLIF(TRIM(prctr), '')
        END AS profit_center_code,
        NULLIF(TRIM(kokrs), '') AS controlling_area,
        NULLIF(TRIM(spras), '') AS language_code,
        NULLIF(TRIM(ktext), '') AS profit_center_short_name,
        NULLIF(TRIM(ltext), '') AS profit_center_name,
        COALESCE(
            TRY_CONVERT(DATE, NULLIF(TRIM(datbi), ''), 112),
            TRY_CONVERT(DATE, NULLIF(TRIM(datbi), ''), 23),
            TRY_CONVERT(DATE, NULLIF(TRIM(datbi), ''))
        ) AS valid_to_date
    FROM stg.stg_cepct
    WHERE NULLIF(TRIM(prctr), '') IS NOT NULL
),
cepct_ranked AS (
    SELECT
        profit_center_code, controlling_area, language_code,
        profit_center_short_name, profit_center_name, valid_to_date,
        ROW_NUMBER() OVER (
            PARTITION BY profit_center_code, controlling_area
            ORDER BY
                CASE WHEN language_code = N'E'  THEN 1
                     WHEN language_code = N'EN' THEN 2
                     WHEN language_code IS NOT NULL THEN 3
                     ELSE 4 END,
                valid_to_date DESC,
                COALESCE(profit_center_name, profit_center_short_name) ASC
        ) AS rn
    FROM cepct_clean
),
pc_joined AS (
    SELECT
        b.profit_center_code,
        b.controlling_area,
        COALESCE(NULLIF(TRIM(t.profit_center_name),       ''),
                 NULLIF(TRIM(t.profit_center_short_name), ''),
                 b.profit_center_code) AS profit_center_name,
        COALESCE(NULLIF(TRIM(t.profit_center_short_name), ''),
                 NULLIF(TRIM(t.profit_center_name),       ''),
                 b.profit_center_code) AS profit_center_short_name,
        b.company_code, b.department, b.responsible_person,
        b.profit_center_group, b.segment, b.currency_code,
        b.country_code, b.region,
        COALESCE(t.valid_to_date, b.valid_to_date) AS valid_to_date,
        t.language_code, b.is_locked, b.is_active
    FROM cepc_best b
    LEFT JOIN cepct_ranked t
        ON b.profit_center_code    = t.profit_center_code
       AND ISNULL(b.controlling_area, N'') = ISNULL(t.controlling_area, N'')
       AND t.rn = 1
)
INSERT INTO dwh.dim_profit_center (
    profit_center_code, controlling_area, profit_center_name,
    profit_center_short_name, company_code, department, responsible_person,
    profit_center_group, segment, currency_code, country_code, region,
    valid_to_date, language_code, is_locked, is_active
)
SELECT
    profit_center_code, controlling_area, profit_center_name,
    profit_center_short_name, company_code, department, responsible_person,
    profit_center_group, segment, currency_code, country_code, region,
    valid_to_date, language_code, is_locked, is_active
FROM pc_joined
WHERE profit_center_code IS NOT NULL;
GO

CREATE INDEX IX_dim_profit_center_code         ON dwh.dim_profit_center (profit_center_code);
CREATE INDEX IX_dim_profit_center_code_company  ON dwh.dim_profit_center (profit_center_code, company_code);
CREATE INDEX IX_dim_profit_center_code_kokrs    ON dwh.dim_profit_center (profit_center_code, controlling_area);
GO

-- ============================================================
-- dim_gl_account
DROP TABLE IF EXISTS dwh.dim_gl_account;
GO

CREATE TABLE dwh.dim_gl_account (
    account_key         INT             IDENTITY(1,1) NOT NULL,
    gl_account          NVARCHAR(20)    NOT NULL,
    chart_of_accounts   NVARCHAR(20)    NULL,
    account_short_name  NVARCHAR(255)   NULL,
    account_long_name   NVARCHAR(255)   NULL,
    account_group       NVARCHAR(20)    NULL,
    -- statement_type: PNL = Profit & Loss, BS = Balance Sheet, UNKNOWN = unmapped
    statement_type      NVARCHAR(20)    NOT NULL,
    is_balance_sheet    BIT             NOT NULL,
    is_active           BIT             NOT NULL CONSTRAINT DF_dim_gl_account_is_active  DEFAULT (1),
    created_at          DATETIME2(0)    NOT NULL CONSTRAINT DF_dim_gl_account_created_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_dim_gl_account PRIMARY KEY (account_key),
    CONSTRAINT UQ_dim_gl_account_gl_account UNIQUE (gl_account)
);
GO

DBCC CHECKIDENT ('dwh.dim_gl_account', RESEED, -1);
GO

SET IDENTITY_INSERT dwh.dim_gl_account ON;
INSERT INTO dwh.dim_gl_account
    (account_key, gl_account, chart_of_accounts, account_short_name,
     account_long_name, account_group, statement_type, is_balance_sheet, is_active)
VALUES
    (0, N'UNKNOWN', NULL, N'Unknown Account', N'Unknown Account', NULL, N'UNKNOWN', 0, 1);
SET IDENTITY_INSERT dwh.dim_gl_account OFF;
GO

;WITH skat_clean AS (
    SELECT
        CASE
            WHEN TRY_CAST(NULLIF(TRIM(saknr), '') AS BIGINT) IS NOT NULL
                THEN CAST(TRY_CAST(NULLIF(TRIM(saknr), '') AS BIGINT) AS NVARCHAR(20))
            ELSE NULLIF(TRIM(saknr), '')
        END AS gl_account,
        NULLIF(TRIM(ktopl), '') AS chart_of_accounts,
        MAX(NULLIF(TRIM(txt20), '')) AS account_short_name,
        MAX(NULLIF(TRIM(txt50), '')) AS account_long_name
    FROM stg.stg_skat
    GROUP BY
        NULLIF(TRIM(ktopl), ''),
        CASE
            WHEN TRY_CAST(NULLIF(TRIM(saknr), '') AS BIGINT) IS NOT NULL
                THEN CAST(TRY_CAST(NULLIF(TRIM(saknr), '') AS BIGINT) AS NVARCHAR(20))
            ELSE NULLIF(TRIM(saknr), '')
        END
),
ska1_clean AS (
    SELECT
        CASE
            WHEN TRY_CAST(NULLIF(TRIM(saknr), '') AS BIGINT) IS NOT NULL
                THEN CAST(TRY_CAST(NULLIF(TRIM(saknr), '') AS BIGINT) AS NVARCHAR(20))
            ELSE NULLIF(TRIM(saknr), '')
        END AS gl_account,
        MAX(NULLIF(TRIM(ktopl), ''))                                          AS chart_of_accounts,
        MAX(UPPER(REPLACE(NULLIF(TRIM(ktoks), ''), '.', '')))                 AS account_group,
        MAX(CASE WHEN NULLIF(TRIM(xbilk), '') = 'X' THEN 1 ELSE 0 END)       AS is_balance_sheet
    FROM stg.stg_ska1
    GROUP BY
        CASE
            WHEN TRY_CAST(NULLIF(TRIM(saknr), '') AS BIGINT) IS NOT NULL
                THEN CAST(TRY_CAST(NULLIF(TRIM(saknr), '') AS BIGINT) AS NVARCHAR(20))
            ELSE NULLIF(TRIM(saknr), '')
        END
),
gl_source AS (
    SELECT
        s.gl_account,
        s.chart_of_accounts,
        COALESCE(k.account_short_name, N'Unknown Account') AS account_short_name,
        COALESCE(k.account_long_name,  N'Unknown Account') AS account_long_name,
        s.account_group,
        -- statement_type to cover SAP standard German account group codes
        CASE
            WHEN s.is_balance_sheet = 1 THEN N'BS'
            WHEN UPPER(s.account_group) IN (
                N'PL', N'GUV', N'E', N'ERLOS', -- P&L: various CoA conventions
                N'K', N'KOST', N'AUFWAND', N'OPA') THEN N'PNL'
            WHEN UPPER(s.account_group) IN (
                N'BS', N'BILANZ', N'A', N'AKTIV', N'P', N'PASSIV',
                N'SA', N'SB') THEN N'BS'
            -- Fallback: derive from numeric range when account_group is not recognized
            WHEN TRY_CAST(s.gl_account AS BIGINT) BETWEEN 100000 AND 399999 THEN N'BS'
            WHEN TRY_CAST(s.gl_account AS BIGINT) BETWEEN 400000 AND 799999 THEN N'PNL'
            ELSE N'UNKNOWN'
        END AS statement_type,
        CAST(s.is_balance_sheet AS BIT) AS is_balance_sheet
    FROM ska1_clean s
    LEFT JOIN skat_clean k
        ON s.chart_of_accounts = k.chart_of_accounts
       AND s.gl_account        = k.gl_account
    WHERE s.gl_account IS NOT NULL
)
INSERT INTO dwh.dim_gl_account
    (gl_account, chart_of_accounts, account_short_name, account_long_name,
     account_group, statement_type, is_balance_sheet, is_active)
SELECT
    gl_account,
    chart_of_accounts,
    account_short_name,
    account_long_name,
    account_group,
    statement_type,
    is_balance_sheet,
    CAST(1 AS BIT)
FROM gl_source;
GO

-- ============================================================
-- dim_account_mapping
-- UNIQUE constraint now covers (gl_account, chart_of_accounts) to support multi-CoA environments
-- This ensures net_amount_local in fact/mart shows Revenue as positive
--  and costs as positive (pre-subtraction), which matches P&L presentation
DROP TABLE IF EXISTS dwh.dim_account_mapping;
GO

CREATE TABLE dwh.dim_account_mapping (
    account_mapping_key  INT             IDENTITY(1,1) NOT NULL,
    gl_account           NVARCHAR(20)    NOT NULL,
    chart_of_accounts    NVARCHAR(20)    NULL,
    pl_group             NVARCHAR(100)   NOT NULL,
    pl_category          NVARCHAR(100)   NOT NULL,
    pl_sort_order        INT             NOT NULL,
    statement_type       NVARCHAR(20)    NOT NULL,
    -- sign_multiplier: -1 for Revenue/Other Income (Credit-normal accounts in SAP)
    -- +1 for COGS/OPEX/Other Expense (Debit-normal accounts)
    -- Usage: net_amount_local = signed_amount_local * sign_multiplier
    -- both Revenue and Costs become positive numbers for P&L reporting
    sign_multiplier      SMALLINT        NOT NULL,
    mapping_rule         NVARCHAR(100)   NOT NULL,
    is_active            BIT             NOT NULL CONSTRAINT DF_dim_account_mapping_is_active  DEFAULT (1),
    created_at           DATETIME2(0)    NOT NULL CONSTRAINT DF_dim_account_mapping_created_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_dim_account_mapping PRIMARY KEY (account_mapping_key),
    CONSTRAINT UQ_dim_account_mapping_gl_coa UNIQUE (gl_account, chart_of_accounts)
);
GO

;WITH gl_source AS (
    SELECT
        CASE
            WHEN TRY_CAST(NULLIF(TRIM(gl_account), '') AS BIGINT) IS NOT NULL
                THEN CAST(TRY_CAST(NULLIF(TRIM(gl_account), '') AS BIGINT) AS NVARCHAR(20))
            ELSE NULLIF(TRIM(gl_account), '')
        END AS gl_account,
        chart_of_accounts,
        account_long_name,
        is_balance_sheet
    FROM dwh.dim_gl_account
    WHERE NULLIF(TRIM(gl_account), '') IS NOT NULL
      AND NULLIF(TRIM(gl_account), '') <> N'UNKNOWN'
),
auto_mapping AS (
    SELECT
        gl_account,
        chart_of_accounts,
        CASE
            WHEN is_balance_sheet = 1                                             THEN N'Balance Sheet'
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 400000 AND 499999         THEN N'Revenue'
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 500000 AND 599999         THEN N'Cost of Sales'
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 600000 AND 699999         THEN N'Operating Expense'
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 700000 AND 749999         THEN N'Other Income'
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 750000 AND 799999         THEN N'Other Expense'
            ELSE N'Unmapped'
        END AS pl_group,
        CASE
            WHEN is_balance_sheet = 1                                             THEN N'Balance Sheet'
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 400000 AND 409999         THEN N'Sales Revenue'
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 410000 AND 419999         THEN N'Service Revenue'
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 420000 AND 499999         THEN N'Other Revenue'
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 500000 AND 549999         THEN N'Direct Cost'
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 550000 AND 599999         THEN N'Pass-through / Logistics Cost'
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 600000 AND 619999         THEN N'Payroll Expense'
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 620000 AND 639999         THEN N'Facility / Admin Expense'
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 640000 AND 659999         THEN N'Selling / Marketing Expense'
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 660000 AND 699999         THEN N'Other Operating Expense'
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 700000 AND 749999         THEN N'Other Income'
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 750000 AND 799999         THEN N'Other Expense'
            ELSE N'Unmapped'
        END AS pl_category,
        CASE
            WHEN is_balance_sheet = 1                                             THEN 999
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 400000 AND 499999         THEN 10
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 500000 AND 599999         THEN 20
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 600000 AND 699999         THEN 30
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 700000 AND 749999         THEN 40
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 750000 AND 799999         THEN 50
            ELSE 999
        END AS pl_sort_order,
        CASE
            WHEN is_balance_sheet = 1                                             THEN N'BS'
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 400000 AND 799999         THEN N'PNL'
            ELSE N'UNMAPPED'
        END AS statement_type,
        -- sign convention clearly documented
        -- Revenue (400000-499999) and Other Income (700000-749999) are Credit-normal in SAP
        -- posted amount_local is negative when revenue is recognized
        -- multiply by -1 to present as positive in P&L
        -- All Costs and Expenses are Debit-normal => already positive, multiply by +1
        CASE
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 400000 AND 499999         THEN CAST(-1 AS SMALLINT)
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 700000 AND 749999         THEN CAST(-1 AS SMALLINT)
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 500000 AND 699999         THEN CAST( 1 AS SMALLINT)
            WHEN TRY_CAST(gl_account AS BIGINT) BETWEEN 750000 AND 799999         THEN CAST( 1 AS SMALLINT)
            ELSE CAST(1 AS SMALLINT)
        END AS sign_multiplier,
        N'Auto Rule: gl_account range' AS mapping_rule
    FROM gl_source
),
-- Manual overrides take priority over auto-mapping
manual_override AS (
    SELECT *
    FROM (VALUES
        (N'500020', NULL, N'Cost of Sales',     N'Pass-through Charges',     25, N'PNL', CAST( 1 AS SMALLINT), N'Manual Override'),
        (N'510006', NULL, N'Operating Expense', N'Repair Material',          35, N'PNL', CAST( 1 AS SMALLINT), N'Manual Override'),
        (N'650085', NULL, N'Operating Expense', N'Subcontracting Services',  36, N'PNL', CAST( 1 AS SMALLINT), N'Manual Override'),
        (N'700400', NULL, N'Other Income',      N'FX Gain',                  40, N'PNL', CAST(-1 AS SMALLINT), N'Manual Override'),
        (N'700800', NULL, N'Other Expense',     N'Customer Rebates',         50, N'PNL', CAST( 1 AS SMALLINT), N'Manual Override')
    ) AS v (gl_account, chart_of_accounts, pl_group, pl_category,
            pl_sort_order, statement_type, sign_multiplier, mapping_rule)
),
final_mapping AS (
    SELECT gl_account, chart_of_accounts, pl_group, pl_category,
           pl_sort_order, statement_type, sign_multiplier, mapping_rule
    FROM manual_override

    UNION ALL

    SELECT a.gl_account, a.chart_of_accounts, a.pl_group, a.pl_category,
           a.pl_sort_order, a.statement_type, a.sign_multiplier, a.mapping_rule
    FROM auto_mapping a
    WHERE NOT EXISTS (
        SELECT 1 FROM manual_override m
        WHERE m.gl_account = a.gl_account
    )
    -- keep only PNL rows in this table — BS accounts are excluded
    AND a.statement_type = N'PNL'
)
INSERT INTO dwh.dim_account_mapping
    (gl_account, chart_of_accounts, pl_group, pl_category, pl_sort_order,
     statement_type, sign_multiplier, mapping_rule, is_active)
SELECT
    gl_account, chart_of_accounts, pl_group, pl_category, pl_sort_order,
    statement_type, sign_multiplier, mapping_rule,
    CAST(1 AS BIT)
FROM final_mapping;
GO
