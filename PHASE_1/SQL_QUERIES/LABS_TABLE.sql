DROP TABLE IF EXISTS #labs

SELECT enc.PAT_ID AS pid
	,ord_res.PAT_ENC_CSN_ID AS hid
	,CASE 
		WHEN lnc.LNC_CODE IS NOT NULL
			THEN 'LONIC CODE'
		WHEN comp.LOINC_CODE IS NOT NULL
			THEN 'LONIC CODE'
		ELSE 'COMPONENT CODE'
		END AS nomenclature
	,COALESCE(lnc.LNC_CODE, comp.LOINC_CODE, CAST(comp.COMPONENT_ID AS VARCHAR)) AS code
	,COALESCE(lnc.LNC_FULL_NAM, comp.NAME) AS NAME
	,enc.HOSP_ADMSN_TIME AS HOSP_ADMIT_DT
	,ord_proc_2.SPECIMN_TAKEN_TIME AS sampleTime
	,DATEDIFF(SECOND, enc.HOSP_ADMSN_TIME, ord_proc_2.SPECIMN_TAKEN_TIME) AS sampleTime_Anonomyzied
	,ord_res.RESULT_TIME AS resultTime
	,DATEDIFF(SECOND, enc.HOSP_ADMSN_TIME, ord_res.RESULT_TIME) AS resultTime_Anonomyzied
	,ord_res.ORD_VALUE AS value
	,comp.DFLT_UNITS AS units
	,ord_proc.ORDER_TIME AS orderTime
	,DATEDIFF(SECOND, enc.HOSP_ADMSN_TIME, ord_proc.ORDER_TIME) AS orderTime_Anonomyzied
INTO #labs
FROM ORDER_RESULTS ord_res
 LEFT JOIN Clarity..ORDER_PROC ord_proc ON ord_proc.ORDER_PROC_ID = ord_res.ORDER_PROC_ID
  LEFT JOIN Clarity..ORDER_PROC_2 ord_proc_2 ON ord_proc.ORDER_PROC_ID = ord_proc_2.ORDER_PROC_ID
  LEFT JOIN Clarity..ZC_ORDER_TYPE zc_ord_type ON ord_proc.ORDER_TYPE_C = zc_ord_type.ORDER_TYPE_C
  LEFT JOIN Clarity..ZC_ORDER_CLASS zc_ord_class ON ord_proc.ORDER_CLASS_C = zc_ord_class.ORDER_CLASS_C
  LEFT JOIN Clarity..ZC_SPECIMEN_TYPE zc_spec_type ON ord_proc.SPECIMEN_TYPE_C = zc_spec_type.SPECIMEN_TYPE_C
  LEFT JOIN Clarity..ZC_SPECIMEN_SOURCE zc_spec_src ON ord_proc.SPECIMEN_SOURCE_C = zc_spec_src.SPECIMEN_SOURCE_C
  LEFT JOIN Clarity..CLARITY_EAP eap ON ord_proc.PROC_ID = eap.PROC_ID
  LEFT JOIN Clarity..CLARITY_COMPONENT comp ON ord_res.COMPONENT_ID = comp.COMPONENT_ID
  LEFT JOIN Clarity..ZC_COMPONENT_TYPE zc_comp_type ON comp.COMPONENT_TYPE_C = zc_comp_type.COMPONENT_TYPE_C
  LEFT JOIN Clarity..ZC_RESULT_FLAG zc_res_flag ON ord_res.RESULT_FLAG_C = zc_res_flag.RESULT_FLAG_C
  LEFT JOIN Clarity..ZC_RESULT_STATUS zc_res_stat ON ord_res.RESULT_STATUS_C = zc_res_stat.RESULT_STATUS_C
  LEFT JOIN CLARITY..ZC_LAB_STATUS zc_lab_stat ON ord_res.LAB_STATUS_C = zc_lab_stat.LAB_STATUS_C
  LEFT JOIN CLARITY..LNC_DB_MAIN lnc ON ord_res.COMPON_LNC_ID = lnc.RECORD_ID
  LEFT JOIN PAT_ENC enc ON enc.PAT_ENC_CSN_ID = ord_res.PAT_ENC_CSN_ID
WHERE ord_res.PAT_ENC_CSN_ID IN (
		SELECT DISTINCT PAT_ENC_CSN_ID
		FROM ##all_enc
		)

SELECT *
FROM #labs

-- Save to .csv file named: PDC_LABS_TABLE.csv
