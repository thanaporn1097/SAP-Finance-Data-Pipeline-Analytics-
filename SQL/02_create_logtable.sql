
-- create pipeline run log and data validation log

DROP TABLE IF EXISTS stg.data_validation_log;
DROP TABLE IF EXISTS stg.pipeline_run_log;
GO

CREATE TABLE stg.pipeline_run_log (
    run_id            INT           IDENTITY(1,1)  PRIMARY KEY,
    pipeline_name     VARCHAR(100)  NOT NULL,
    run_timestamp     DATETIME      NOT NULL  DEFAULT GETDATE(),
    end_timestamp     DATETIME      NULL,
    duration_seconds  AS (
        CASE WHEN end_timestamp IS NOT NULL
             THEN DATEDIFF(SECOND, run_timestamp, end_timestamp)
             ELSE NULL END
    ) PERSISTED,
    status            VARCHAR(20)   NOT NULL,   -- STARTED | SUCCESS | FAILED
    rows_affected     INT           NULL,
    note              VARCHAR(2000) NULL
);
GO

CREATE INDEX IX_pipeline_run_log_name_ts
    ON stg.pipeline_run_log (pipeline_name, run_timestamp DESC);
GO

CREATE TABLE stg.data_validation_log (
    validation_log_id INT           IDENTITY(1,1)  PRIMARY KEY,
    run_id            INT           NULL,
    check_timestamp   DATETIME      NOT NULL  DEFAULT GETDATE(),
    table_name        VARCHAR(100)  NOT NULL,
    check_name        VARCHAR(100)  NOT NULL,
    -- LOAD | DUPLICATE | NULL_KEY | BALANCE | DATE_RANGE | ROW_COUNT | OTHER
    check_category    VARCHAR(50)   NOT NULL  DEFAULT 'OTHER',
    issue_count       INT           NOT NULL,
    status            VARCHAR(20)   NOT NULL,   -- PASSED | WARNING | FAILED
    note              VARCHAR(2000) NULL,
    -- sample bad values e.g. first 5 unmatched keys for quick diagnosis
    sample_values     VARCHAR(2000) NULL,
    CONSTRAINT FK_data_validation_log_run_id
        FOREIGN KEY (run_id) REFERENCES stg.pipeline_run_log (run_id)
);
GO

CREATE INDEX IX_data_validation_log_run_status
    ON stg.data_validation_log (run_id, status);
GO

CREATE INDEX IX_data_validation_log_table_check
    ON stg.data_validation_log (table_name, check_name);
GO
