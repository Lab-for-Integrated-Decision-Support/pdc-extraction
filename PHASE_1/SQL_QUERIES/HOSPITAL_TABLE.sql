DROP TABLE IF EXISTS #race_p
DROP TABLE IF EXISTS #ethincity_p
DROP TABLE IF EXISTS #hospital

--Race
SELECT p.PAT_ID
	,STRING_AGG(race_c.NAME, '|') AS RACE -- STIRNG_AGG for SQL SERVER 2017 and later
INTO #race_p
FROM PATIENT p
JOIN PATIENT_RACE race ON p.PAT_ID = race.PAT_ID
JOIN ZC_PATIENT_RACE race_c ON race_c.PATIENT_RACE_C = race.PATIENT_RACE_C
WHERE p.PAT_ID IN (
		SELECT DISTINCT PAT_ID
		FROM ##all_enc
		)
GROUP BY p.PAT_ID

-- Ethnicity
SELECT p.PAT_ID
	,STRING_AGG(eth_c.NAME, '|') AS ETHNICNITY -- STIRNG_AGG for SQL SERVER 2017 and later
INTO #ethincity_p
FROM PATIENT p
JOIN ETHNIC_BACKGROUND eth ON p.PAT_ID = eth.PAT_ID
JOIN ZC_ETHNIC_BKGRND eth_c ON eth_c.ETHNIC_BKGRND_C = eth.ETHNIC_BKGRND_C
WHERE p.PAT_ID IN (
		SELECT DISTINCT PAT_ID
		FROM ##all_enc
		)
GROUP BY p.PAT_ID

-- Hospital
SELECT enc.PAT_ID AS pid
	,enc.PAT_ENC_CSN_ID AS hid
	,MIN(SEX) AS sex
	,MIN(BIRTH_DATE) AS BIRTH_DATE
	,MIN(HOSP_ADMIT_DT) AS HOSP_ADMIT_DT
	,MIN(DATEDIFF(DAY, BIRTH_DATE, HOSP_ADMIT_DT)) AS ageAtAdmission_Anonomyzied
	,MIN(HOSP_DC_DT) AS HOSP_DC_DT
	,MIN(DATEDIFF(SECOND, HOSP_ADMIT_DT, HOSP_DC_DT)) AS hospitalDischarge_Anonomyzied
	,MIN(RACE) AS RACE
	,MIN(ETHNICNITY) AS ETHNICNITY
	,MAX(CASE 
			WHEN DISCH_DISP_C <> '20'
				THEN '0'
			WHEN DISCH_DISP_C = '20'
				AND ICU_OUT_DT < HOSP_DC_DT
				THEN '1'
			ELSE '0'
			END) AS hospitalMortality
	,MIN(DATEPART(YEAR, HOSP_ADMIT_DT)) AS yearOfAdmission
INTO #hospital
FROM ##all_enc enc
LEFT JOIN #race_p rce ON enc.PAT_ID = rce.PAT_ID
LEFT JOIN #ethincity_p eth ON enc.PAT_ID = eth.PAT_ID
GROUP BY enc.PAT_ID
	,enc.PAT_ENC_CSN_ID
ORDER BY enc.PAT_ID

SELECT *
FROM #hospital


-- Save to .csv file named: PDC_HOSPITAL_TABLE.csv