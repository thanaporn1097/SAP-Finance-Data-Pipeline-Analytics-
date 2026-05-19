**Finance Data Pipeline Project**

📌 **Overview**

This project demonstrates an end-to-end finance data pipeline, transforming raw SAP datasets into structured analytical datasets for financial reporting and decision-making.

⚙️ **Architecture**

<img width="1536" height="1024" alt="Data Architecture_SAP_Finance_Project" src="https://github.com/user-attachments/assets/9a65cc0f-6103-4d21-aab7-030eb36711b3" />

The pipeline consists of:

Data ingestion using Python
Data transformation and storage in SQL (Staging → DWH → Mart)
Data modeling using Star Schema
Visualization using Power BI dashboards

🧱 **Data Model**

A star schema was designed to support financial analysis:

Fact table: fact_gl_postings
Dimensions: dim_company, dim_customer, dim_month, dim_date, dim_profit_center, dim_gl_account, dim_account_mapping

🧪 **Data Quality**

Implemented validation checks:
data_validation_log
pipeline_run_log

📊 Dashboard

Developed Power BI dashboards to analyze:

Executive Summary
P&L Monthly

🚀 Impact
Reduced manual reporting time by ~90%
Enabled structured and scalable financial analysis
Improved data accuracy and reliability



