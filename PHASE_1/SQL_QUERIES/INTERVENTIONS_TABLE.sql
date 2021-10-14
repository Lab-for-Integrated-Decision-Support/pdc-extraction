DROP TABLE IF EXISTS #interventions

DECLARE @Intervention_FloIDs TABLE (
	FloId VARCHAR(50)
	,DisplayName VARCHAR(150) NULL
	)

INSERT INTO @Intervention_FloIDs
VALUES (
	'10'
	,'PULSE OXIMETRY'
	)
	,(
	'8'
	,'PULSE'
	)

SELECT 
	 pat.PAT_ID as pid
	,enc.PAT_ENC_CSN_ID as hid
	,fs_meas.FSD_ID as code
	,fs_meas.RECORDED_TIME as startTime
	,DATEDIFF_BIG(SECOND, pat.BIRTH_DATE, RECORDED_TIME) AS startTime_Anonymized
	,fs_meas.MEAS_VALUE as value
	,flo.UNITS as units
	,zc_doc_src.NAME AS source
	,flo.DISP_NAME as name
INTO #interventions
FROM Clarity..IP_FLWSHT_MEAS fs_meas
LEFT JOIN Clarity..IP_FLWSHT_REC fs_rec ON fs_meas.FSD_ID = fs_rec.FSD_ID
LEFT JOIN Clarity..PAT_ENC_HSP enc ON enc.INPATIENT_DATA_ID = fs_rec.INPATIENT_DATA_ID
LEFT JOIN Clarity..ZC_FLO_DOC_SRC zc_doc_src ON fs_meas.DOCUMENTATION_SOURCE_C = zc_doc_src.DOCUMENTATION_SOURCE_C
LEFT JOIN Clarity..IP_FLO_GP_DATA flo ON fs_meas.FLO_MEAS_ID = flo.FLO_MEAS_ID
LEFT JOIN PATIENT pat ON enc.PAT_ID = pat.PAT_ID
WHERE enc.PAT_ENC_CSN_ID IN (
		SELECT DISTINCT PAT_ENC_CSN_ID
		FROM ##all_enc
		)
	AND fs_meas.FLO_MEAS_ID IN (
		SELECT DISTINCT FloId
		FROM @Intervention_FloIDs
		)

SELECT *
FROM #interventions

-- Save to .csv file named: PDC_Interventions.csv
