SELECT fs_meas.FLO_MEAS_ID
	,min(flo.FLO_MEAS_NAME collate SQL_Latin1_General_Cp1251_CS_AS) AS FLO_MEAS_NAME
	,min(flo.DISP_NAME) AS DisplayName
	,COUNT(fs_meas.FLO_MEAS_ID) AS 'OCCURANCES'
INTO #floIds
FROM Clarity..IP_FLWSHT_MEAS fs_meas
LEFT JOIN Clarity..IP_FLWSHT_REC fs_rec ON fs_meas.FSD_ID = fs_rec.FSD_ID
LEFT JOIN Clarity..PAT_ENC_HSP enc ON enc.INPATIENT_DATA_ID = fs_rec.INPATIENT_DATA_ID
LEFT JOIN Clarity..IP_FLO_GP_DATA flo ON fs_meas.FLO_MEAS_ID = flo.FLO_MEAS_ID
LEFT JOIN ##all_enc ON enc.PAT_ENC_CSN_ID = ##all_enc.PAT_ENC_CSN_ID
WHERE enc.PAT_ENC_CSN_ID IN (
		SELECT PAT_ENC_CSN_ID
		FROM ##all_enc
		)
	AND fs_meas.RECORDED_TIME >= ##all_enc.ICU_IN_DT
	AND fs_meas.RECORDED_TIME <= ##all_enc.ICU_OUT_DT
GROUP BY fs_meas.FLO_MEAS_ID

SELECT *
FROM #floIds
ORDER BY OCCURANCES DESC