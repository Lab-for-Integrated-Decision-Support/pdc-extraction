-- ICU Table
-- icuMedicalDischarge requires VPS data, this will be in Phase 2
DROP TABLE IF EXISTS #icu

SELECT PAT_ID AS pid
	,EVENT_ID AS eid
	,PAT_ENC_CSN_ID AS hid
	,DEPT_GRP AS icu
	,ICU_IN_DT AS icuAdmission
	,DATEDIFF(SECOND, HOSP_ADMIT_DT, ICU_IN_DT) AS icuAdmission_Anonomyzied
	,ICU_OUT_DT AS icuDischarge
	,DATEDIFF(SECOND, HOSP_ADMIT_DT, ICU_OUT_DT) AS icuDischarge_Anonomyzied
	,DISCH_DISP AS icuDisposition
	,CASE 
		WHEN DISCH_DISP_C <> '20'
			THEN '0'
		WHEN DISCH_DISP_C = '20'
			AND ICU_OUT_DT = HOSP_DC_DT
			THEN '1'
		ELSE '0'
		END AS icuMortality
INTO #icu
FROM ##all_enc

SELECT *
FROM #icu


-- Save to .csv file named: PDC_ICU_TABLE.csv
