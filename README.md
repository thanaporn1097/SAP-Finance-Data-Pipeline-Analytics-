**Finance Data Pipeline Project**

📌 **Overview**

This project demonstrates an end-to-end finance data pipeline, transforming raw SAP datasets into structured analytical datasets for financial reporting and decision-making.

**Dataset Source:**

SAP DATASET | BigQuery Dataset from Kaggle
https://www.kaggle.com/datasets/mustafakeser4/sap-dataset-bigquery-dataset/data

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

Mart: pl_monthly
<img width="1392" height="387" alt="image" src="https://github.com/user-attachments/assets/1a6dde32-bd62-4f1a-9fd1-57e501b0ba42" />

🧪 **Data Quality**

Implemented validation checks:

pipeline_run_log
<img width="1092" height="117" alt="image" src="https://github.com/user-attachments/assets/649e5134-89ce-4cf2-9a65-dc0235e106bf" />

data_validation_log
<img width="1252" height="382" alt="image" src="https://github.com/user-attachments/assets/48877248-d5c4-46e2-a15f-09952cf97cfe" />


📊 Dashboard

Developed Power BI dashboards to analyze:

Executive Summary
<img width="1296" height="722" alt="image" src="https://github.com/user-attachments/assets/639e3b5c-83c3-4e65-b5eb-2fa6183c1f4f" />


P&L Monthly
<img width="1287" height="720" alt="image" src="https://github.com/user-attachments/assets/840b7d83-a066-4a0b-9cce-dbd6b0c6cf4d" />


🚀 Impact
Reduced manual reporting time by ~90%
Enabled structured and scalable financial analysis
Improved data accuracy and reliability



