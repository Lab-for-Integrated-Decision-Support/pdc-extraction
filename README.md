# pdc-extraction


This repository will be used to store all queries, functions and general code to execute the extraction of data via the Clarity database for the PICU Data Collective (PDC).

This process will be rolled out in a phased approach. 

- Phase 1 will be the SQL queries to pull data out of Clarity. 
- Phase 2 will be written in R and will take the data from phase 1 and transform, filter, and anonymize the data in accordance to the PDC data model. 

The SQL queries are written for Microsoft SQL Server, there is a goal to write the queries for the other SQL platforms (MySQL, Big Query, etc) in the future.

If you have an issue or question, please submit an [issue](https://github.com/Lab-for-Integrated-Decision-Support/pdc-extraction/issues): and we will investigate.

## The Phases

### Phase 1: SQL Queries
Since most data will originate from the Clarity database, SQL queries will be used in phase 1 to obtain the data. This will avoid most connection issues and subsequent   troubleshooting required when using third-party applications to access the database. **The results from the SQL queries will need to be saved out to .csv files.** 

These queries will connect to the Clarity database and return base tables for each of the required extracts for the PDC. 

The crucial part of phase 1 is the ALL_ENCOUNTERS.sql query. This will make a temp table ##all_enc, this is the main cohort for the PDC extract. All other queries use the ##all_enc table. Therefore, after ALL_ENCOUNTERS.sql is run, the query needs to remain open in the SQL session in order to access the ##all_enc table. 

There is a visual representation of the phase 1 workflow in the repositiory. The workflow document has some key notes for each query. You can find it below:

[Workflow](https://github.com/Lab-for-Integrated-Decision-Support/pdc-extraction/blob/63465d361f8d7466ab34cda203e665dc5631ba6f/PHASE_1/PDC%20Extract%20Work%20Flow.pdf)
	

### Phase 2: R Scripts Transform and Anonymize

	Coming Soon
