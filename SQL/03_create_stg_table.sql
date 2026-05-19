-- create_stg_table.sql
-- 1. Accounting Document Header (BKPF)
DROP TABLE IF EXISTS stg.stg_bkpf;
GO
CREATE TABLE stg.stg_bkpf (
    mandt            NVARCHAR(MAX),   -- Client
    bukrs            NVARCHAR(MAX),   -- Company Code
    belnr            NVARCHAR(MAX),   -- Accounting Document Number
    gjahr            NVARCHAR(MAX),   -- Fiscal Year
    blart            NVARCHAR(MAX),   -- Document Type
    bldat            NVARCHAR(MAX),   -- Document Date
    budat            NVARCHAR(MAX),   -- Posting Date
    waers            NVARCHAR(MAX),   -- Currency Key
    xblnr            NVARCHAR(MAX),   -- Reference Document Number
    usnam            NVARCHAR(MAX),   -- User Name
    source_file_name VARCHAR(MAX),
    load_timestamp   DATETIME
);
GO

-- 2. Accounting Document Segment (BSEG)
DROP TABLE IF EXISTS stg.stg_bseg;
GO
CREATE TABLE stg.stg_bseg (
    -- FIX: added mandt — present in source CSV but was missing from original DDL
    --      without this, rows from different clients (e.g. 050 vs 100) cannot be distinguished
    mandt            NVARCHAR(MAX),   -- Client
    bukrs            NVARCHAR(MAX),   -- Company Code
    belnr            NVARCHAR(MAX),   -- Document Number
    gjahr            NVARCHAR(MAX),   -- Fiscal Year
    bschl            NVARCHAR(MAX),   -- Posting Key
    koart            NVARCHAR(MAX),   -- Account Type (D=Customer, K=Vendor, S=GL)
    buzei            NVARCHAR(MAX),   -- Line Item Number
    hkont            NVARCHAR(MAX),   -- General Ledger Account
    dmbtr            NVARCHAR(MAX),   -- Amount in Local Currency
    wrbtr            NVARCHAR(MAX),   -- Amount in Document Currency
    shkzg            NVARCHAR(MAX),   -- Debit/Credit Indicator (S=Debit, H=Credit)
    kunnr            NVARCHAR(MAX),   -- Customer Number
    lifnr            NVARCHAR(MAX),   -- Vendor Number
    kostl            NVARCHAR(MAX),   -- Cost Center
    augdt            NVARCHAR(MAX),   -- Clearing Date
    augbl            NVARCHAR(MAX),   -- Clearing Document
    prctr            NVARCHAR(MAX),   -- Profit Center
    zfbdt            NVARCHAR(MAX),   -- Baseline Date for Payment
    zterm            NVARCHAR(MAX),   -- Payment Terms
    umskz            NVARCHAR(MAX),   -- Special G/L Indicator
    rebzg            NVARCHAR(MAX),   -- Invoice Reference
    sgtxt            NVARCHAR(MAX),   -- Item Text
    zuonr            NVARCHAR(MAX),   -- Assignment Number
    zbd1t            NVARCHAR(MAX),   -- Cash Discount Days 1
    segment          NVARCHAR(MAX),   -- Segment for Segment Reporting
    source_file_name VARCHAR(MAX),
    load_timestamp   DATETIME
);
GO

-- 3. G/L Account Description (SKAT)
DROP TABLE IF EXISTS stg.stg_skat;
GO
CREATE TABLE stg.stg_skat (
    ktopl            NVARCHAR(MAX),   -- Chart of Accounts
    saknr            NVARCHAR(MAX),   -- G/L Account Number
    txt20            NVARCHAR(MAX),   -- Short Text
    txt50            NVARCHAR(MAX),   -- Long Text
    source_file_name VARCHAR(MAX),
    load_timestamp   DATETIME
);
GO

-- 4. G/L Account Master Data — Chart of Accounts (SKA1)
DROP TABLE IF EXISTS stg.stg_ska1;
GO
CREATE TABLE stg.stg_ska1 (
    ktopl            NVARCHAR(MAX),   -- Chart of Accounts
    saknr            NVARCHAR(MAX),   -- G/L Account Number
    xbilk            NVARCHAR(MAX),   -- Balance Sheet Account Flag (X=Yes)
    bilkt            NVARCHAR(MAX),   -- Group Account Number
    ktoks            NVARCHAR(MAX),   -- Account Group
    source_file_name VARCHAR(MAX),
    load_timestamp   DATETIME
);
GO

-- 5. Customer Master Data (KNA1)
DROP TABLE IF EXISTS stg.stg_kna1;
GO
CREATE TABLE stg.stg_kna1 (
    kunnr            NVARCHAR(MAX),   -- Customer Number
    name1            NVARCHAR(MAX),   -- Customer Name
    land1            NVARCHAR(MAX),   -- Country Key
    regio            NVARCHAR(MAX),   -- Region
    ort01            NVARCHAR(MAX),   -- City
    brsch            NVARCHAR(MAX),   -- Industry Key
    ktokd            NVARCHAR(MAX),   -- Account Group
    source_file_name VARCHAR(MAX),
    load_timestamp   DATETIME
);
GO

-- 6. Profit Center Master Data (CEPC)
DROP TABLE IF EXISTS stg.stg_cepc;
GO
CREATE TABLE stg.stg_cepc (
    prctr            NVARCHAR(MAX),   -- Profit Center
    kokrs            NVARCHAR(MAX),   -- Controlling Area
    bukrs            NVARCHAR(MAX),   -- Company Code
    abtei            NVARCHAR(MAX),   -- Department
    verak            NVARCHAR(MAX),   -- Responsible Person
    khinr            NVARCHAR(MAX),   -- Profit Center Hierarchy Node
    segment          NVARCHAR(MAX),   -- Segment
    waers            NVARCHAR(MAX),   -- Currency Key
    land1            NVARCHAR(MAX),   -- Country Key
    regio            NVARCHAR(MAX),   -- Region
    datbi            NVARCHAR(MAX),   -- Valid To Date
    lock_ind         NVARCHAR(MAX),   -- Lock Indicator
    is_deleted       NVARCHAR(MAX),   -- ETL Deleted Flag
    source_file_name VARCHAR(MAX),
    load_timestamp   DATETIME
);
GO

-- 7. Billing Document Header (VBRK)
DROP TABLE IF EXISTS stg.stg_vbrk;
GO
CREATE TABLE stg.stg_vbrk (
    vbeln            NVARCHAR(MAX),   -- Billing Document Number
    fkdat            NVARCHAR(MAX),   -- Billing Date
    bukrs            NVARCHAR(MAX),   -- Company Code
    vkorg            NVARCHAR(MAX),   -- Sales Organization
    vtweg            NVARCHAR(MAX),   -- Distribution Channel
    kunag            NVARCHAR(MAX),   -- Sold-To Customer
    kunrg            NVARCHAR(MAX),   -- Payer
    waerk            NVARCHAR(MAX),   -- Currency
    gjahr            NVARCHAR(MAX),   -- Fiscal Year
    poper            NVARCHAR(MAX),   -- Fiscal Period
    fkart            NVARCHAR(MAX),   -- Billing Type
    source_file_name VARCHAR(MAX),
    load_timestamp   DATETIME
);
GO

-- 8. Billing Document Item (VBRP)
DROP TABLE IF EXISTS stg.stg_vbrp;
GO
CREATE TABLE stg.stg_vbrp (
    vbeln            NVARCHAR(MAX),   -- Billing Document Number
    posnr            NVARCHAR(MAX),   -- Item Number
    matnr            NVARCHAR(MAX),   -- Material Number
    netwr            NVARCHAR(MAX),   -- Net Value
    mwsbp            NVARCHAR(MAX),   -- VAT Amount
    kunag            NVARCHAR(MAX),   -- Sold-To Party
    fkdat            NVARCHAR(MAX),   -- Billing Date
    source_file_name VARCHAR(MAX),
    load_timestamp   DATETIME
);
GO

-- 9. Company Codes (T001)
DROP TABLE IF EXISTS stg.stg_t001;
GO
CREATE TABLE stg.stg_t001 (
    bukrs            NVARCHAR(MAX),   -- Company Code
    butxt            NVARCHAR(MAX),   -- Company Name
    source_file_name VARCHAR(MAX),
    load_timestamp   DATETIME
);
GO

-- 10. Profit Center Text (CEPCT)
DROP TABLE IF EXISTS stg.stg_cepct;
GO
CREATE TABLE stg.stg_cepct (
    spras            NVARCHAR(MAX),   -- Language Key
    prctr            NVARCHAR(MAX),   -- Profit Center
    kokrs            NVARCHAR(MAX),   -- Controlling Area
    datab            NVARCHAR(MAX),   -- Valid From Date
    datbi            NVARCHAR(MAX),   -- Valid To Date
    ktext            NVARCHAR(MAX),   -- Short Text
    ltext            NVARCHAR(MAX),   -- Long Text
    source_file_name NVARCHAR(MAX),
    load_timestamp   DATETIME
);
GO
