-- Create mart.pl_monthly and mart.pl_budget_monthly

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- mart.pl_monthly — Actual P&L by month/company/profit center/account
DROP TABLE IF EXISTS mart.pl_monthly;
GO

CREATE TABLE mart.pl_monthly (
    pl_monthly_key        INT             IDENTITY(1,1) NOT NULL,

    company_key           INT             NOT NULL,
    company_code          NVARCHAR(20)    NULL,
    company_name          NVARCHAR(100)   NULL,

    month_key             INT             NOT NULL,
    calendar_year         INT             NOT NULL,
    month_no              INT             NOT NULL,
    year_month_label      NVARCHAR(20)    NULL,

    profit_center_key     INT             NOT NULL,
    profit_center_code    NVARCHAR(20)    NOT NULL,
    profit_center_name    NVARCHAR(255)   NOT NULL,
    department            NVARCHAR(100)   NOT NULL,

    account_key           INT             NOT NULL,
    gl_account            NVARCHAR(20)    NOT NULL,
    account_short_name    NVARCHAR(255)   NULL,

    pl_group              NVARCHAR(100)   NOT NULL,
    pl_category           NVARCHAR(100)   NOT NULL,
    pl_sort_order         INT             NOT NULL,
    -- only 'PNL' allowed — 'P&L' variant removed for consistency
    statement_type        NVARCHAR(20)    NOT NULL,

    posting_line_count    INT             NOT NULL,
    -- amount_local: raw signed amount (Revenue=negative, Costs=positive per SAP convention)
    amount_local          DECIMAL(18,2)   NOT NULL,
    -- net_amount_local: presentation amount = amount_local * sign_multiplier
    -- Revenue: negative * -1 = positive (shown as revenue earned)
    -- COGS/OPEX: positive * 1 = positive (shown as cost incurred)
    net_amount_local      DECIMAL(18,2)   NOT NULL,

    CONSTRAINT PK_mart_pl_monthly PRIMARY KEY (pl_monthly_key)
);
GO

INSERT INTO mart.pl_monthly (
    company_key, company_code, company_name,
    month_key, calendar_year, month_no, year_month_label,
    profit_center_key, profit_center_code, profit_center_name, department,
    account_key, gl_account, account_short_name,
    pl_group, pl_category, pl_sort_order, statement_type,
    posting_line_count, amount_local, net_amount_local
)
SELECT
    f.company_key,
    c.company_code,
    c.company_name,
    d.month_key,
    d.calendar_year,
    d.month_no,
    d.year_month_label,
    COALESCE(f.prctr_key, 0)                                    AS profit_center_key,
    COALESCE(pc.profit_center_code, N'UNKNOWN')                 AS profit_center_code,
    COALESCE(pc.profit_center_name, N'Unknown Profit Center')   AS profit_center_name,
    COALESCE(pc.department, N'Unknown')                         AS department,
    f.account_key,
    a.gl_account,
    a.account_short_name,
    m.pl_group,
    m.pl_category,
    m.pl_sort_order,
    -- FIX: standardized to 'PNL' only
    N'PNL'                                                      AS statement_type,
    COUNT(*)                                                    AS posting_line_count,
    CAST(SUM(ISNULL(f.signed_amount_local, 0)) AS DECIMAL(18,2)) AS amount_local,
    -- Revenue accounts: signed_amount is negative (Credit-normal), sign_multiplier=-1 => positive
    -- COGS/OPEX: signed_amount is positive (Debit-normal), sign_multiplier=+1 => positive
    CAST(SUM(ISNULL(f.signed_amount_local, 0) * ISNULL(m.sign_multiplier, 1)) AS DECIMAL(18,2)) AS net_amount_local
FROM dwh.fact_gl_postings f
INNER JOIN dwh.dim_company c
    ON f.company_key   = c.company_key
INNER JOIN dwh.dim_gl_account a
    ON f.account_key   = a.account_key
INNER JOIN dwh.dim_date d
    ON f.posting_date_key = d.date_key
INNER JOIN dwh.dim_account_mapping m
    ON a.gl_account    = m.gl_account
LEFT JOIN dwh.dim_profit_center pc
    ON f.prctr_key     = pc.prctr_key
-- Exclude the default 'UNKNOWN' date row and rows with unresolved months
WHERE d.date_key <> 0
  AND f.month_key <> 0
  -- 'P&L' variant removed — only 'PNL' is used
  AND m.statement_type = N'PNL'
  -- Exclude Balance Sheet accounts from P&L mart
  AND a.is_balance_sheet = 0
GROUP BY
    f.company_key, c.company_code, c.company_name,
    d.month_key, d.calendar_year, d.month_no, d.year_month_label,
    COALESCE(f.prctr_key, 0),
    COALESCE(pc.profit_center_code, N'UNKNOWN'),
    COALESCE(pc.profit_center_name, N'Unknown Profit Center'),
    COALESCE(pc.department, N'Unknown'),
    f.account_key, a.gl_account, a.account_short_name,
    m.pl_group, m.pl_category, m.pl_sort_order;
GO

-- Unique grain index (separate from PK)
CREATE UNIQUE INDEX UQ_mart_pl_monthly_grain
    ON mart.pl_monthly (company_key, month_key, profit_center_key, account_key);
GO
CREATE INDEX IX_mart_pl_monthly_month_key          ON mart.pl_monthly (month_key);
CREATE INDEX IX_mart_pl_monthly_company_month      ON mart.pl_monthly (company_key, month_key);
CREATE INDEX IX_mart_pl_monthly_profit_center_month ON mart.pl_monthly (profit_center_key, month_key);
CREATE INDEX IX_mart_pl_monthly_account_key        ON mart.pl_monthly (account_key);
GO