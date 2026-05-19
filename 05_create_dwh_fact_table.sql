
-- create_dwh_fact_table.sql
-- ============================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DROP TABLE IF EXISTS dwh.fact_gl_postings;
GO

CREATE TABLE dwh.fact_gl_postings (
    gl_posting_key         INT             IDENTITY(1,1) NOT NULL,
    company_key            INT             NOT NULL,
    account_key            INT             NOT NULL,
    customer_key           INT             NOT NULL,
    prctr_key              INT             NOT NULL,

    document_date_key      INT             NOT NULL,
    posting_date_key       INT             NOT NULL,
    month_key              INT             NOT NULL,

    document_date          DATE            NULL,
    posting_date           DATE            NULL,

    company_code           NVARCHAR(10)    NOT NULL,
    gl_account             NVARCHAR(20)    NOT NULL,
    document_number        NVARCHAR(20)    NOT NULL,
    fiscal_year            INT             NULL,
    line_item_no           INT             NULL,

    document_type          NVARCHAR(10)    NULL,
    currency_code          NVARCHAR(10)    NULL,
    reference_number       NVARCHAR(50)    NULL,
    user_name              NVARCHAR(255)   NULL,
    -- H = Haben (Credit), S = Soll (Debit) — SAP standard
    debit_credit_indicator NVARCHAR(5)     NULL,

    amount_local           DECIMAL(18,2)   NULL,
    -- signed_amount_local: positive for Debit (S), negative for Credit (H)
    -- This preserves the raw accounting sign before P&L sign_multiplier is applied
    signed_amount_local    DECIMAL(18,2)   NULL,

    customer_code          NVARCHAR(20)    NULL,
    vendor_code            NVARCHAR(20)    NULL,
    cost_center_code       NVARCHAR(20)    NULL,
    profit_center_code     NVARCHAR(20)    NULL,
    segment                NVARCHAR(255)   NULL,
    clearing_document      NVARCHAR(20)    NULL,

    source_file_name       VARCHAR(255)    NULL,
    load_timestamp         DATETIME        NULL,

    CONSTRAINT PK_fact_gl_postings PRIMARY KEY (gl_posting_key),
    CONSTRAINT FK_fact_gl_postings_company       FOREIGN KEY (company_key)       REFERENCES dwh.dim_company(company_key),
    CONSTRAINT FK_fact_gl_postings_account       FOREIGN KEY (account_key)       REFERENCES dwh.dim_gl_account(account_key),
    CONSTRAINT FK_fact_gl_postings_customer      FOREIGN KEY (customer_key)      REFERENCES dwh.dim_customer(customer_key),
    CONSTRAINT FK_fact_gl_postings_profit_center FOREIGN KEY (prctr_key)         REFERENCES dwh.dim_profit_center(prctr_key),
    CONSTRAINT FK_fact_gl_postings_document_date FOREIGN KEY (document_date_key) REFERENCES dwh.dim_date(date_key),
    CONSTRAINT FK_fact_gl_postings_posting_date  FOREIGN KEY (posting_date_key)  REFERENCES dwh.dim_date(date_key)
);
GO
-- DATA QUALITY CHECK: Document-level debit/credit balance
-- Logs any document where SUM(Debit) <> SUM(Credit) to validation log

DECLARE @run_id INT;
SELECT @run_id = MAX(run_id) FROM stg.pipeline_run_log;

INSERT INTO stg.data_validation_log
    (run_id, table_name, check_name, issue_count, status, note)
SELECT
    @run_id,
    'stg.stg_bseg',
    'debit_credit_balance_check',
    COUNT(*),
    CASE WHEN COUNT(*) = 0 THEN 'PASSED' ELSE 'WARNING' END,
    CASE WHEN COUNT(*) = 0
         THEN 'All documents are balanced (debit = credit)'
         ELSE CONCAT(CAST(COUNT(*) AS VARCHAR), ' documents are unbalanced — check source data')
    END
FROM (
    SELECT
        NULLIF(TRIM(bukrs), '') AS company_code,
        NULLIF(TRIM(belnr), '') AS document_number,
        TRY_CONVERT(INT, NULLIF(TRIM(gjahr), '')) AS fiscal_year,
        SUM(
            CASE
                WHEN NULLIF(TRIM(shkzg), '') = N'S'
                THEN  ISNULL(TRY_CONVERT(DECIMAL(18,2), REPLACE(REPLACE(TRIM(dmbtr), ',', ''), ' ', '')), 0)
                WHEN NULLIF(TRIM(shkzg), '') = N'H'
                THEN -ISNULL(TRY_CONVERT(DECIMAL(18,2), REPLACE(REPLACE(TRIM(dmbtr), ',', ''), ' ', '')), 0)
                ELSE 0
            END
        ) AS net_balance
    FROM stg.stg_bseg
    WHERE NULLIF(TRIM(bukrs), '') IS NOT NULL
      AND NULLIF(TRIM(belnr), '') IS NOT NULL
    GROUP BY
        NULLIF(TRIM(bukrs), ''),
        NULLIF(TRIM(belnr), ''),
        TRY_CONVERT(INT, NULLIF(TRIM(gjahr), ''))
    HAVING ABS(SUM(
        CASE
            WHEN NULLIF(TRIM(shkzg), '') = N'S'
            THEN  ISNULL(TRY_CONVERT(DECIMAL(18,2), REPLACE(REPLACE(TRIM(dmbtr), ',', ''), ' ', '')), 0)
            WHEN NULLIF(TRIM(shkzg), '') = N'H'
            THEN -ISNULL(TRY_CONVERT(DECIMAL(18,2), REPLACE(REPLACE(TRIM(dmbtr), ',', ''), ' ', '')), 0)
            ELSE 0
        END
    )) > 0.01   -- allow 1 cent rounding tolerance
) AS unbalanced_docs;
GO
-- DATA QUALITY CHECK — posting dates not in dim_date
-- These rows will resolve to posting_date_key=0 (UNKNOWN)
-- and month_key=0, causing them to be excluded from mart.pl_monthly

DECLARE @run_id2 INT;
SELECT @run_id2 = MAX(run_id) FROM stg.pipeline_run_log;

INSERT INTO stg.data_validation_log
    (run_id, table_name, check_name, issue_count, status, note)
SELECT
    @run_id2,
    'stg.stg_bkpf',
    'posting_date_in_dim_date_check',
    COUNT(*),
    CASE WHEN COUNT(*) = 0 THEN 'PASSED' ELSE 'WARNING' END,
    CASE WHEN COUNT(*) = 0
         THEN 'All posting dates exist in dim_date'
         ELSE CONCAT(CAST(COUNT(*) AS VARCHAR),
              ' posting dates not found in dim_date — these rows will have month_key=0 and be excluded from mart')
    END
FROM stg.stg_bkpf b
WHERE NOT EXISTS (
    SELECT 1 FROM dwh.dim_date d
    WHERE d.full_date = COALESCE(
        TRY_CONVERT(DATE, NULLIF(TRIM(b.budat), ''), 112),
        TRY_CONVERT(DATE, NULLIF(TRIM(b.budat), ''), 23),
        TRY_CONVERT(DATE, NULLIF(TRIM(b.budat), ''), 120),
        TRY_CONVERT(DATE, NULLIF(TRIM(b.budat), ''))
    )
)
AND NULLIF(TRIM(b.budat), '') IS NOT NULL;
GO

-- INSERT into fact_gl_postings

;WITH header_base AS (
    SELECT
        NULLIF(LTRIM(RTRIM(bukrs)), '')                                       AS company_code,
        NULLIF(LTRIM(RTRIM(belnr)), '')                                       AS document_number,
        TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(gjahr)), ''))                     AS fiscal_year,
        NULLIF(LTRIM(RTRIM(blart)), '')                                       AS document_type,
        COALESCE(
            TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM(bldat)), ''), 112),
            TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM(bldat)), ''), 23),
            TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM(bldat)), ''), 120),
            TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM(bldat)), ''))
        ) AS document_date,
        COALESCE(
            TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM(budat)), ''), 112),
            TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM(budat)), ''), 23),
            TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM(budat)), ''), 120),
            TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM(budat)), ''))
        ) AS posting_date,
        NULLIF(LTRIM(RTRIM(waers)), '')                                       AS currency_code,
        NULLIF(LTRIM(RTRIM(xblnr)), '')                                       AS reference_number,
        NULLIF(LTRIM(RTRIM(usnam)), '')                                       AS user_name,
        source_file_name,
        load_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY
                NULLIF(LTRIM(RTRIM(bukrs)), ''),
                NULLIF(LTRIM(RTRIM(belnr)), ''),
                TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(gjahr)), ''))
            ORDER BY load_timestamp DESC, source_file_name DESC
        ) AS rn
    FROM stg.stg_bkpf
    WHERE NULLIF(LTRIM(RTRIM(bukrs)), '') IS NOT NULL
      AND NULLIF(LTRIM(RTRIM(belnr)), '') IS NOT NULL
),
header_clean AS (
    SELECT company_code, document_number, fiscal_year, document_type,
           document_date, posting_date, currency_code, reference_number,
           user_name, source_file_name, load_timestamp
    FROM header_base
    WHERE rn = 1
),
line_base AS (
    SELECT
        NULLIF(TRIM(bukrs), '')                                               AS company_code,
        NULLIF(TRIM(belnr), '')                                               AS document_number,
        TRY_CONVERT(INT, NULLIF(TRIM(gjahr), ''))                             AS fiscal_year,
        TRY_CONVERT(INT, NULLIF(TRIM(buzei), ''))                             AS line_item_no,
        CASE
            WHEN TRY_CAST(NULLIF(TRIM(hkont), '') AS BIGINT) IS NOT NULL
                THEN CAST(TRY_CAST(NULLIF(TRIM(hkont), '') AS BIGINT) AS NVARCHAR(20))
            ELSE NULLIF(TRIM(hkont), '')
        END AS gl_account,
        NULLIF(TRIM(shkzg), '')                                               AS debit_credit_indicator,
        CASE
            WHEN NULLIF(TRIM(dmbtr), '') IS NULL THEN NULL
            ELSE TRY_CONVERT(DECIMAL(18,2), REPLACE(REPLACE(TRIM(dmbtr), ',', ''), ' ', ''))
        END AS amount_local,
        NULLIF(TRIM(kunnr), '')                                               AS customer_code,
        NULLIF(TRIM(lifnr), '')                                               AS vendor_code,
        NULLIF(TRIM(kostl), '')                                               AS cost_center_code,
        CASE
            WHEN TRY_CAST(NULLIF(TRIM(prctr), '') AS BIGINT) IS NOT NULL
                THEN CAST(TRY_CAST(NULLIF(TRIM(prctr), '') AS BIGINT) AS NVARCHAR(20))
            ELSE NULLIF(TRIM(prctr), '')
        END AS profit_center_code,
        NULLIF(TRIM(segment), '')                                             AS segment,
        NULLIF(TRIM(augbl),   '')                                             AS clearing_document,
        source_file_name,
        load_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY
                NULLIF(TRIM(bukrs), ''),
                NULLIF(TRIM(belnr), ''),
                TRY_CONVERT(INT, NULLIF(TRIM(gjahr), '')),
                TRY_CONVERT(INT, NULLIF(TRIM(buzei), '')),
                CASE WHEN TRY_CAST(NULLIF(TRIM(hkont), '') AS BIGINT) IS NOT NULL
                     THEN CAST(TRY_CAST(NULLIF(TRIM(hkont), '') AS BIGINT) AS NVARCHAR(20))
                     ELSE NULLIF(TRIM(hkont), '') END,
                NULLIF(TRIM(shkzg), ''),
                CASE WHEN NULLIF(TRIM(dmbtr), '') IS NULL THEN NULL
                     ELSE TRY_CONVERT(DECIMAL(18,2), REPLACE(REPLACE(TRIM(dmbtr), ',', ''), ' ', '')) END,
                NULLIF(TRIM(kunnr), ''),
                NULLIF(TRIM(lifnr), ''),
                NULLIF(TRIM(kostl), ''),
                CASE WHEN TRY_CAST(NULLIF(TRIM(prctr), '') AS BIGINT) IS NOT NULL
                     THEN CAST(TRY_CAST(NULLIF(TRIM(prctr), '') AS BIGINT) AS NVARCHAR(20))
                     ELSE NULLIF(TRIM(prctr), '') END,
                NULLIF(TRIM(segment), ''),
                NULLIF(TRIM(augbl),   '')
            ORDER BY load_timestamp DESC, source_file_name DESC
        ) AS rn_exact
    FROM stg.stg_bseg
    WHERE NULLIF(TRIM(bukrs), '') IS NOT NULL
      AND NULLIF(TRIM(belnr), '') IS NOT NULL
      AND NULLIF(TRIM(hkont), '') IS NOT NULL
),
line_clean AS (
    SELECT company_code, document_number, fiscal_year, line_item_no,
           gl_account, debit_credit_indicator, amount_local,
           customer_code, vendor_code, cost_center_code, profit_center_code,
           segment, clearing_document, source_file_name, load_timestamp
    FROM line_base
    WHERE rn_exact = 1
),
joined_source AS (
    SELECT
        h.company_code,
        l.gl_account,
        h.document_number,
        h.fiscal_year,
        l.line_item_no,
        h.document_type,
        h.document_date,
        h.posting_date,
        h.currency_code,
        h.reference_number,
        h.user_name,
        l.debit_credit_indicator,
        l.amount_local,
        -- signed_amount_local: Debit(S)=positive, Credit(H)=negative
        -- Revenue accounts are Credit-normal, so signed_amount will be negative
        -- sign_multiplier in dim_account_mapping will flip it to positive for reporting
        CASE
            WHEN l.amount_local IS NULL               THEN NULL
            WHEN l.debit_credit_indicator = N'H'      THEN -1 * ABS(l.amount_local)
            WHEN l.debit_credit_indicator = N'S'      THEN      ABS(l.amount_local)
            ELSE l.amount_local
        END AS signed_amount_local,
        l.customer_code,
        l.vendor_code,
        l.cost_center_code,
        l.profit_center_code,
        l.segment,
        l.clearing_document,
        COALESCE(l.source_file_name, h.source_file_name) AS source_file_name,
        COALESCE(l.load_timestamp,   h.load_timestamp)   AS load_timestamp
    FROM header_clean h
    INNER JOIN line_clean l
        ON  h.company_code   = l.company_code
        AND h.document_number = l.document_number
        AND ISNULL(h.fiscal_year, -1) = ISNULL(l.fiscal_year, -1)
)
INSERT INTO dwh.fact_gl_postings (
    company_key, account_key, customer_key, prctr_key,
    document_date_key, posting_date_key, month_key,
    document_date, posting_date,
    company_code, gl_account, document_number, fiscal_year, line_item_no,
    document_type, currency_code, reference_number, user_name,
    debit_credit_indicator, amount_local, signed_amount_local,
    customer_code, vendor_code, cost_center_code, profit_center_code,
    segment, clearing_document, source_file_name, load_timestamp
)
SELECT
    COALESCE(dc.company_key,  0)                                            AS company_key,
    COALESCE(da.account_key,  0)                                            AS account_key,
    COALESCE(dcu.customer_key, 0)                                           AS customer_key,
    COALESCE(dp.prctr_key,    0)                                            AS prctr_key,
    COALESCE(ddoc.date_key,   0)                                            AS document_date_key,
    COALESCE(dpost.date_key,  0)                                            AS posting_date_key,
    -- month_key comes ONLY from dim_date to guarantee consistency with dim_month
    -- If posting_date is not in dim_date (key resolves to 0), month_key = 0
    -- The data quality check above logs how many rows are affected
    COALESCE(dpost.month_key, 0)                                            AS month_key,
    js.document_date,
    js.posting_date,
    js.company_code,
    js.gl_account,
    js.document_number,
    js.fiscal_year,
    js.line_item_no,
    js.document_type,
    js.currency_code,
    js.reference_number,
    js.user_name,
    js.debit_credit_indicator,
    js.amount_local,
    js.signed_amount_local,
    js.customer_code,
    js.vendor_code,
    js.cost_center_code,
    js.profit_center_code,
    js.segment,
    js.clearing_document,
    js.source_file_name,
    js.load_timestamp
FROM joined_source js
LEFT JOIN dwh.dim_company dc
    ON js.company_code = dc.company_code
LEFT JOIN dwh.dim_gl_account da
    ON js.gl_account   = da.gl_account
LEFT JOIN dwh.dim_customer dcu
    ON js.customer_code = dcu.customer_code
OUTER APPLY (
    SELECT TOP (1) p.prctr_key
    FROM dwh.dim_profit_center p
    WHERE p.profit_center_code = js.profit_center_code
    ORDER BY
        CASE WHEN p.company_code = js.company_code THEN 1 ELSE 2 END,
        CASE WHEN p.is_active    = 1               THEN 1 ELSE 2 END,
        CASE WHEN p.controlling_area IS NULL        THEN 2 ELSE 1 END,
        p.prctr_key
) dp
LEFT JOIN dwh.dim_date ddoc
    ON js.document_date = ddoc.full_date
LEFT JOIN dwh.dim_date dpost
    ON js.posting_date  = dpost.full_date;
GO

CREATE INDEX IX_fact_gl_postings_posting_date_key  ON dwh.fact_gl_postings (posting_date_key);
CREATE INDEX IX_fact_gl_postings_month_key          ON dwh.fact_gl_postings (month_key);
CREATE INDEX IX_fact_gl_postings_document_date_key  ON dwh.fact_gl_postings (document_date_key);
CREATE INDEX IX_fact_gl_postings_account_key        ON dwh.fact_gl_postings (account_key);
CREATE INDEX IX_fact_gl_postings_company_key        ON dwh.fact_gl_postings (company_key);
CREATE INDEX IX_fact_gl_postings_customer_key       ON dwh.fact_gl_postings (customer_key);
CREATE INDEX IX_fact_gl_postings_prctr_key          ON dwh.fact_gl_postings (prctr_key);
CREATE INDEX IX_fact_gl_postings_company_month      ON dwh.fact_gl_postings (company_key, month_key);
CREATE INDEX IX_fact_gl_postings_business_keys
    ON dwh.fact_gl_postings (company_code, document_number, fiscal_year, line_item_no, gl_account);
GO
