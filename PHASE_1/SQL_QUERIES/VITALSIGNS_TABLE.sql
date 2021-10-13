DROP TABLE IF EXISTS #vitals

DECLARE @Vital_FloIDs TABLE (
	FloId VARCHAR(50)
	,DisplayName VARCHAR(150) NULL
	)

INSERT INTO @Vital_FloIDs
VALUES (
	'10'
	,'PULSE OXIMETRY'
	)
	,(
	'8'
	,'PULSE'
	)

SELECT fs_meas.FSD_ID
	,enc.PAT_ENC_CSN_ID
	,pat.BIRTH_DATE
	-- Flowsheet Measure
	,fs_meas.LINE
	,fs_meas.FLO_MEAS_ID
	,fs_meas.RECORDED_TIME
	,DATEDIFF_BIG(SECOND, BIRTH_DATE, RECORDED_TIME) AS RECORDED_TIME_Anonymized
	,fs_meas.ENTRY_TIME
	,fs_meas.MEAS_VALUE
	,flo.UNITS
	,zc_doc_src.NAME AS DOCUMENTATION_SRC
	-- Flowsheet
	,flo.FLO_MEAS_NAME collate SQL_Latin1_General_Cp1251_CS_AS AS FLO_MEAS_NAME
	,flo.DISP_NAME
	,zc_row_typ.NAME AS ROW_TYPE
	,zc_val_typ.NAME AS VAL_TYPE
	-- Template
	,fs_meas.FLT_ID
	,flt.TEMPLATE_NAME
	,flt.DISPLAY_NAME
	-- FS Record
	,fs_rec.RECORD_DATE
	,fs_rec.DAILY_NET
INTO #vitals
FROM Clarity..IP_FLWSHT_MEAS fs_meas
LEFT JOIN Clarity..IP_FLWSHT_REC fs_rec ON fs_meas.FSD_ID = fs_rec.FSD_ID
LEFT JOIN Clarity..PAT_ENC_HSP enc ON enc.INPATIENT_DATA_ID = fs_rec.INPATIENT_DATA_ID
LEFT JOIN Clarity..IP_FLT_DATA flt ON flt.TEMPLATE_ID = fs_meas.FLT_ID
LEFT JOIN Clarity..ZC_FLO_DOC_SRC zc_doc_src ON fs_meas.DOCUMENTATION_SOURCE_C = zc_doc_src.DOCUMENTATION_SOURCE_C
LEFT JOIN Clarity..IP_FLO_GP_DATA flo ON fs_meas.FLO_MEAS_ID = flo.FLO_MEAS_ID
LEFT JOIN Clarity..ZC_ROW_TYP zc_row_typ ON flo.ROW_TYP_C = zc_row_typ.ROW_TYP_C
LEFT JOIN Clarity..ZC_VAL_TYPE zc_val_typ ON flo.VAL_TYPE_C = zc_val_typ.VAL_TYPE_C
LEFT JOIN PATIENT pat ON enc.PAT_ID = pat.PAT_ID
WHERE enc.PAT_ENC_CSN_ID IN (
		SELECT DISTINCT PAT_ENC_CSN_ID
		FROM ##all_enc
		)
	AND fs_meas.FLO_MEAS_ID IN (
		SELECT DISTINCT FloId
		FROM @Vital_FloIDs
		)

SELECT *
FROM #vitals

-- Save to .csv file named: PDC_VitalSigns.csv
