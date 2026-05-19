/* ============================================================================
   github_portfolio_validation_and_analyst_v2.sql
   Purpose:
   Portfolio-ready validation checks + analyst showcase queries

   This version avoids derived-table aliases like ') x' in summary inserts
   to improve SQL Server compatibility.
   ============================================================================ */

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('tempdb..#validation_summary') IS NOT NULL
    DROP TABLE #validation_summary;

CREATE TABLE #validation_summary (
    check_name       NVARCHAR(100) NOT NULL,
    issue_count      INT           NOT NULL,
    expected_result  NVARCHAR(50)  NOT NULL,
    why_it_matters   NVARCHAR(255) NOT NULL
);

/* ============================================================================
   CHECK 01
   Duplicate active P&L mappings
   Expected: 0 rows
   ============================================================================ */
SELECT
    N'CHECK_01_duplicate_active_pnl_mapping' AS check_name,
    m.gl_account,
    m.chart_of_accounts,
    COUNT(*) AS mapping_row_count
FROM dwh.dim_account_mapping m
WHERE m.statement_type = N'PNL'
  AND m.is_active = 1
GROUP BY
    m.gl_account,
    m.chart_of_accounts
HAVING COUNT(*) > 1
ORDER BY mapping_row_count DESC, m.gl_account;

;WITH check_01 AS (
    SELECT m.gl_account, m.chart_of_accounts
    FROM dwh.dim_account_mapping m
    WHERE m.statement_type = N'PNL'
      AND m.is_active = 1
    GROUP BY m.gl_account, m.chart_of_accounts
    HAVING COUNT(*) > 1
)
INSERT INTO #validation_summary (check_name, issue_count, expected_result, why_it_matters)
SELECT
    N'CHECK_01_duplicate_active_pnl_mapping',
    COUNT(*),
    N'0 rows',
    N'Prevents duplicated amounts when building mart.pl_monthly'
FROM check_01;

/* ============================================================================
   CHECK 02
   Unmapped active P&L GL accounts
   Expected: 0 rows
   ============================================================================ */
SELECT
    N'CHECK_02_unmapped_active_pnl_gl' AS check_name,
    a.gl_account,
    a.chart_of_accounts,
    a.account_long_name,
    a.statement_type,
    a.is_balance_sheet
FROM dwh.dim_gl_account a
LEFT JOIN dwh.dim_account_mapping m
    ON  a.gl_account = m.gl_account
    AND ISNULL(a.chart_of_accounts, N'') = ISNULL(m.chart_of_accounts, N'')
    AND m.statement_type = N'PNL'
    AND m.is_active = 1
WHERE a.statement_type = N'PNL'
  AND a.is_balance_sheet = 0
  AND m.gl_account IS NULL
ORDER BY a.gl_account;

;WITH check_02 AS (
    SELECT a.gl_account
    FROM dwh.dim_gl_account a
    LEFT JOIN dwh.dim_account_mapping m
        ON  a.gl_account = m.gl_account
        AND ISNULL(a.chart_of_accounts, N'') = ISNULL(m.chart_of_accounts, N'')
        AND m.statement_type = N'PNL'
        AND m.is_active = 1
    WHERE a.statement_type = N'PNL'
      AND a.is_balance_sheet = 0
      AND m.gl_account IS NULL
)
INSERT INTO #validation_summary (check_name, issue_count, expected_result, why_it_matters)
SELECT
    N'CHECK_02_unmapped_active_pnl_gl',
    COUNT(*),
    N'0 rows',
    N'Confirms all in-scope P&L accounts are classified for reporting'
FROM check_02;

/* ============================================================================
   CHECK 03
   Unexpected debit / credit indicator values in fact table
   Expected: 0 rows
   ============================================================================ */
SELECT
    N'CHECK_03_unexpected_debit_credit_indicator' AS check_name,
    ISNULL(f.debit_credit_indicator, N'<NULL>') AS debit_credit_indicator,
    COUNT(*) AS row_count
FROM dwh.fact_gl_postings f
WHERE ISNULL(f.debit_credit_indicator, N'') NOT IN (N'H', N'S', N'')
GROUP BY ISNULL(f.debit_credit_indicator, N'<NULL>')
ORDER BY debit_credit_indicator;

;WITH check_03 AS (
    SELECT 1 AS issue_flag
    FROM dwh.fact_gl_postings f
    WHERE ISNULL(f.debit_credit_indicator, N'') NOT IN (N'H', N'S', N'')
)
INSERT INTO #validation_summary (check_name, issue_count, expected_result, why_it_matters)
SELECT
    N'CHECK_03_unexpected_debit_credit_indicator',
    COUNT(*),
    N'0 rows',
    N'Confirms signed amounts are driven by expected accounting indicators'
FROM check_03;

/* ============================================================================
   CHECK 04
   Mart formula check
   Rule: net_amount_local must equal amount_local * sign_multiplier
   Expected: 0 rows
   ============================================================================ */
SELECT
    N'CHECK_04_mart_formula_mismatch' AS check_name,
    m.company_code,
    m.year_month_label,
    m.profit_center_code,
    m.gl_account,
    m.pl_group,
    m.pl_category,
    map.sign_multiplier,
    m.amount_local,
    m.net_amount_local,
    CAST(m.amount_local * ISNULL(map.sign_multiplier, 1) AS DECIMAL(18,2)) AS expected_net_amount_local
FROM mart.pl_monthly m
INNER JOIN dwh.dim_gl_account a
    ON m.account_key = a.account_key
INNER JOIN dwh.dim_account_mapping map
    ON  a.gl_account = map.gl_account
    AND ISNULL(a.chart_of_accounts, N'') = ISNULL(map.chart_of_accounts, N'')
    AND map.statement_type = N'PNL'
    AND map.is_active = 1
WHERE m.net_amount_local <> CAST(m.amount_local * ISNULL(map.sign_multiplier, 1) AS DECIMAL(18,2))
ORDER BY m.year_month_label, m.gl_account;

;WITH check_04 AS (
    SELECT 1 AS issue_flag
    FROM mart.pl_monthly m
    INNER JOIN dwh.dim_gl_account a
        ON m.account_key = a.account_key
    INNER JOIN dwh.dim_account_mapping map
        ON  a.gl_account = map.gl_account
        AND ISNULL(a.chart_of_accounts, N'') = ISNULL(map.chart_of_accounts, N'')
        AND map.statement_type = N'PNL'
        AND map.is_active = 1
    WHERE m.net_amount_local <> CAST(m.amount_local * ISNULL(map.sign_multiplier, 1) AS DECIMAL(18,2))
)
INSERT INTO #validation_summary (check_name, issue_count, expected_result, why_it_matters)
SELECT
    N'CHECK_04_mart_formula_mismatch',
    COUNT(*),
    N'0 rows',
    N'Validates report-ready amounts used in charts and KPI visuals'
FROM check_04;

/* ============================================================================
   CHECK 05
   Fact-to-mart reconciliation at mart grain
   Expected: 0 rows
   ============================================================================ */
;WITH expected AS (
    SELECT
        f.company_key,
        d.month_key,
        COALESCE(f.prctr_key, 0) AS profit_center_key,
        f.account_key,
        COUNT(*) AS expected_posting_line_count,
        CAST(SUM(ISNULL(f.signed_amount_local, 0)) AS DECIMAL(18,2)) AS expected_amount_local,
        CAST(SUM(ISNULL(f.signed_amount_local, 0) * ISNULL(map.sign_multiplier, 1)) AS DECIMAL(18,2)) AS expected_net_amount_local
    FROM dwh.fact_gl_postings f
    INNER JOIN dwh.dim_gl_account a
        ON f.account_key = a.account_key
    INNER JOIN dwh.dim_date d
        ON f.posting_date_key = d.date_key
    INNER JOIN dwh.dim_account_mapping map
        ON  a.gl_account = map.gl_account
        AND ISNULL(a.chart_of_accounts, N'') = ISNULL(map.chart_of_accounts, N'')
        AND map.statement_type = N'PNL'
        AND map.is_active = 1
    WHERE d.date_key <> 0
      AND f.month_key <> 0
      AND a.is_balance_sheet = 0
    GROUP BY
        f.company_key,
        d.month_key,
        COALESCE(f.prctr_key, 0),
        f.account_key
)
SELECT
    N'CHECK_05_fact_to_mart_reconciliation' AS check_name,
    COALESCE(m.company_key, e.company_key) AS company_key,
    COALESCE(m.month_key, e.month_key) AS month_key,
    COALESCE(m.profit_center_key, e.profit_center_key) AS profit_center_key,
    COALESCE(m.account_key, e.account_key) AS account_key,
    m.posting_line_count AS mart_posting_line_count,
    e.expected_posting_line_count,
    m.amount_local AS mart_amount_local,
    e.expected_amount_local,
    m.net_amount_local AS mart_net_amount_local,
    e.expected_net_amount_local
FROM mart.pl_monthly m
FULL OUTER JOIN expected e
    ON  m.company_key = e.company_key
    AND m.month_key = e.month_key
    AND m.profit_center_key = e.profit_center_key
    AND m.account_key = e.account_key
WHERE ISNULL(m.posting_line_count, -1) <> ISNULL(e.expected_posting_line_count, -1)
   OR ISNULL(m.amount_local, 0) <> ISNULL(e.expected_amount_local, 0)
   OR ISNULL(m.net_amount_local, 0) <> ISNULL(e.expected_net_amount_local, 0)
ORDER BY COALESCE(m.month_key, e.month_key), COALESCE(m.account_key, e.account_key);

;WITH expected AS (
    SELECT
        f.company_key,
        d.month_key,
        COALESCE(f.prctr_key, 0) AS profit_center_key,
        f.account_key,
        COUNT(*) AS expected_posting_line_count,
        CAST(SUM(ISNULL(f.signed_amount_local, 0)) AS DECIMAL(18,2)) AS expected_amount_local,
        CAST(SUM(ISNULL(f.signed_amount_local, 0) * ISNULL(map.sign_multiplier, 1)) AS DECIMAL(18,2)) AS expected_net_amount_local
    FROM dwh.fact_gl_postings f
    INNER JOIN dwh.dim_gl_account a
        ON f.account_key = a.account_key
    INNER JOIN dwh.dim_date d
        ON f.posting_date_key = d.date_key
    INNER JOIN dwh.dim_account_mapping map
        ON  a.gl_account = map.gl_account
        AND ISNULL(a.chart_of_accounts, N'') = ISNULL(map.chart_of_accounts, N'')
        AND map.statement_type = N'PNL'
        AND map.is_active = 1
    WHERE d.date_key <> 0
      AND f.month_key <> 0
      AND a.is_balance_sheet = 0
    GROUP BY
        f.company_key,
        d.month_key,
        COALESCE(f.prctr_key, 0),
        f.account_key
),
check_05 AS (
    SELECT 1 AS issue_flag
    FROM mart.pl_monthly m
    FULL OUTER JOIN expected e
        ON  m.company_key = e.company_key
        AND m.month_key = e.month_key
        AND m.profit_center_key = e.profit_center_key
        AND m.account_key = e.account_key
    WHERE ISNULL(m.posting_line_count, -1) <> ISNULL(e.expected_posting_line_count, -1)
       OR ISNULL(m.amount_local, 0) <> ISNULL(e.expected_amount_local, 0)
       OR ISNULL(m.net_amount_local, 0) <> ISNULL(e.expected_net_amount_local, 0)
)
INSERT INTO #validation_summary (check_name, issue_count, expected_result, why_it_matters)
SELECT
    N'CHECK_05_fact_to_mart_reconciliation',
    COUNT(*),
    N'0 rows',
    N'Proves mart.pl_monthly is a reliable reporting layer built from fact data'
FROM check_05;

/* ============================================================================
   CHECK 06
   Duplicate mart grain
   Expected: 0 rows
   ============================================================================ */
SELECT
    N'CHECK_06_duplicate_mart_grain' AS check_name,
    company_key,
    month_key,
    profit_center_key,
    account_key,
    COUNT(*) AS row_count
FROM mart.pl_monthly
GROUP BY
    company_key,
    month_key,
    profit_center_key,
    account_key
HAVING COUNT(*) > 1
ORDER BY row_count DESC;

;WITH check_06 AS (
    SELECT 1 AS issue_flag
    FROM mart.pl_monthly
    GROUP BY company_key, month_key, profit_center_key, account_key
    HAVING COUNT(*) > 1
)
INSERT INTO #validation_summary (check_name, issue_count, expected_result, why_it_matters)
SELECT
    N'CHECK_06_duplicate_mart_grain',
    COUNT(*),
    N'0 rows',
    N'Confirms the reporting mart has a stable and non-duplicated grain'
FROM check_06;

/* ============================================================================
   CHECK 07
   Validation summary table
   ============================================================================ */
SELECT
    check_name,
    issue_count,
    expected_result,
    CASE WHEN issue_count = 0 THEN N'PASS' ELSE N'REVIEW' END AS status,
    why_it_matters
FROM #validation_summary
ORDER BY check_name;

/* ============================================================================
   ANALYST SHOWCASE 01
   Monthly P&L summary from mart.pl_monthly
   ============================================================================ */
SELECT
    m.month_key,
    m.year_month_label,
    CAST(SUM(CASE WHEN m.pl_group = N'Revenue'           THEN m.net_amount_local ELSE 0 END) AS DECIMAL(18,2)) AS revenue,
    CAST(SUM(CASE WHEN m.pl_group = N'Other Income'      THEN m.net_amount_local ELSE 0 END) AS DECIMAL(18,2)) AS other_income,
    CAST(SUM(CASE WHEN m.pl_group = N'Cost of Sales'     THEN m.net_amount_local ELSE 0 END) AS DECIMAL(18,2)) AS cost_of_sales,
    CAST(SUM(CASE WHEN m.pl_group = N'Operating Expense' THEN m.net_amount_local ELSE 0 END) AS DECIMAL(18,2)) AS operating_expense,
    CAST(SUM(CASE WHEN m.pl_group = N'Other Expense'     THEN m.net_amount_local ELSE 0 END) AS DECIMAL(18,2)) AS other_expense,
    CAST(
        SUM(CASE WHEN m.pl_group IN (N'Revenue', N'Other Income') THEN m.net_amount_local ELSE 0 END)
        - SUM(CASE WHEN m.pl_group IN (N'Cost of Sales', N'Operating Expense', N'Other Expense') THEN m.net_amount_local ELSE 0 END)
        AS DECIMAL(18,2)
    ) AS operating_profit,
    CAST(
        100.0 * (
            SUM(CASE WHEN m.pl_group IN (N'Revenue', N'Other Income') THEN m.net_amount_local ELSE 0 END)
            - SUM(CASE WHEN m.pl_group IN (N'Cost of Sales', N'Operating Expense', N'Other Expense') THEN m.net_amount_local ELSE 0 END)
        ) / NULLIF(SUM(CASE WHEN m.pl_group = N'Revenue' THEN m.net_amount_local ELSE 0 END), 0)
        AS DECIMAL(9,2)
    ) AS operating_margin_pct
FROM mart.pl_monthly m
GROUP BY m.month_key, m.year_month_label
ORDER BY m.month_key;

/* ============================================================================
   ANALYST SHOWCASE 02
   Top expense categories
   ============================================================================ */
SELECT TOP (10)
    m.pl_category,
    CAST(SUM(m.net_amount_local) AS DECIMAL(18,2)) AS total_expense_amount,
    CAST(
        100.0 * SUM(m.net_amount_local)
        / NULLIF(SUM(SUM(m.net_amount_local)) OVER (), 0)
        AS DECIMAL(9,2)
    ) AS expense_share_pct
FROM mart.pl_monthly m
WHERE m.pl_group IN (N'Cost of Sales', N'Operating Expense', N'Other Expense')
GROUP BY m.pl_category
ORDER BY total_expense_amount DESC;

/* ============================================================================
   ANALYST SHOWCASE 03
   Lowest-performing profit centers
   ============================================================================ */
SELECT TOP (10)
    m.profit_center_code,
    m.profit_center_name,
    CAST(SUM(CASE WHEN m.pl_group IN (N'Revenue', N'Other Income') THEN m.net_amount_local ELSE 0 END) AS DECIMAL(18,2)) AS total_income,
    CAST(SUM(CASE WHEN m.pl_group IN (N'Cost of Sales', N'Operating Expense', N'Other Expense') THEN m.net_amount_local ELSE 0 END) AS DECIMAL(18,2)) AS total_cost,
    CAST(
        SUM(CASE WHEN m.pl_group IN (N'Revenue', N'Other Income') THEN m.net_amount_local ELSE 0 END)
        - SUM(CASE WHEN m.pl_group IN (N'Cost of Sales', N'Operating Expense', N'Other Expense') THEN m.net_amount_local ELSE 0 END)
        AS DECIMAL(18,2)
    ) AS operating_profit
FROM mart.pl_monthly m
GROUP BY m.profit_center_code, m.profit_center_name
ORDER BY operating_profit ASC;

DROP TABLE #validation_summary;
