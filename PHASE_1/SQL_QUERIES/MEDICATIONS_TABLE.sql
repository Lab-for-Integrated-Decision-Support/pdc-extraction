DROP TABLE IF EXISTS #rxnorm
DROP TABLE IF EXISTS #meds

SELECT rxnorm.MEDICATION_ID
	,MAX(RXNORM_CODE) AS rxnormcode
	,MAX('RXNORM CODE') AS nomenclature
INTO #rxnorm
FROM RXNORM_CODES rxnorm
INNER JOIN (
	SELECT MEDICATION_ID
		,MAX(RXNORM_TERM_TYPE_C) AS max_term_type
	--,MAX(RXNORM_CODE) AS rxnormcode
	FROM RXNORM_CODES
	WHERE (
			RXNORM_CODE_LEVEL_C = '1'
			OR RXNORM_CODE_LEVEL_C IS NULL
			)
		AND (
			RXNORM_TERM_TYPE_C IN (
				'1'
				,'3'
				)
			OR RXNORM_TERM_TYPE_C IS NULL
			)
	GROUP BY MEDICATION_ID
	) grp ON (
		rxnorm.MEDICATION_ID = grp.MEDICATION_ID
		AND rxnorm.RXNORM_TERM_TYPE_C = grp.max_term_type
		)
GROUP BY rxnorm.MEDICATION_ID

SELECT enc.PAT_ID
	,mar.ORDER_MED_ID
	,ord_med.PAT_ENC_CSN_ID
	,mar.LINE
	,mar.TAKEN_TIME
	,zc_time_src.NAME AS MAR_TIME_SRC
	,zc_mar_rslt.NAME AS MAR_ACTION
	,mar.SIG
	,zc_adm_rt.NAME AS ADMIN_ROUTE
	,med.ROUTE AS MED_ROUTE
	,zc_mar_rsn.NAME AS MAR_REASON
	,mar.INFUSION_RATE
	,zc_inf_unit.NAME AS MAR_INF_RATE_UNIT
	,zc_unit.NAME AS DOSE_UNIT
	,mar.MAR_DURATION
	,zc_dur_un.NAME AS MAR_DURATION_UNIT
	,dep.DEPARTMENT_NAME AS MED_ADMIN_DEPT_NAME
	,ord_med.MEDICATION_ID
	,ord_med.DESCRIPTION
	,ord_med.DISPLAY_NAME
	,zc_ord_stat.NAME AS ORDER_STATUS
	,med.NAME AS MED_NAME
	,zc_thera.NAME AS THERA_CLASS
	,zc_pharm.NAME AS PHARM_CLASS
	,zc_subpharm.NAME AS PHARM_SUBCLASS
	,zc_sg.NAME AS SIMPLE_GENERIC
	,COALESCE(rxnorm.rxnormcode, ord_med.MEDICATION_ID) AS code
	,COALESCE(rxnorm.nomenclature, 'MEDICATION ID') AS nomenclature
INTO #meds
FROM Clarity..MAR_ADMIN_INFO mar
LEFT JOIN Clarity..ORDER_MED ord_med ON ord_med.ORDER_MED_ID = mar.ORDER_MED_ID
LEFT JOIN Clarity..ZC_MAR_TIME_SRC zc_time_src ON mar.MAR_TIME_SOURCE_C = zc_time_src.MAR_TIME_SRC_C
LEFT JOIN Clarity..ZC_MAR_RSLT zc_mar_rslt ON mar.MAR_ACTION_C = zc_mar_rslt.RESULT_C
LEFT JOIN Clarity..ZC_ADMIN_ROUTE zc_adm_rt ON mar.ROUTE_C = zc_adm_rt.MED_ROUTE_C
LEFT JOIN Clarity..ZC_MAR_RSN zc_mar_rsn ON mar.REASON_C = zc_mar_rsn.REASON_C
LEFT JOIN Clarity..ZC_MED_UNIT zc_inf_unit ON mar.MAR_INF_RATE_UNIT_C = zc_inf_unit.DISP_QTYUNIT_C
LEFT JOIN Clarity..ZC_MED_UNIT zc_unit ON mar.DOSE_UNIT_C = zc_unit.DISP_QTYUNIT_C
LEFT JOIN Clarity..ZC_MED_DURATION_UN zc_dur_un ON mar.MAR_DURATION_UNIT_C = zc_dur_un.MED_DURATION_UN_C
LEFT JOIN Clarity..CLARITY_DEP dep ON mar.MAR_ADMIN_DEPT_ID = dep.DEPARTMENT_ID
LEFT JOIN Clarity..ORDER_MEDINFO ord_med_info ON ord_med.ORDER_MED_ID = ord_med_info.ORDER_MED_ID
LEFT JOIN Clarity..CLARITY_MEDICATION med ON ord_med_info.DISPENSABLE_MED_ID = med.MEDICATION_ID
LEFT JOIN Clarity..ZC_ORDER_STATUS zc_ord_stat ON ord_med.ORDER_STATUS_C = zc_ord_stat.ORDER_STATUS_C
LEFT JOIN Clarity..ZC_THERA_CLASS zc_thera ON med.THERA_CLASS_C = zc_thera.THERA_CLASS_C
LEFT JOIN Clarity..ZC_PHARM_CLASS zc_pharm ON med.PHARM_CLASS_C = zc_pharm.PHARM_CLASS_C
LEFT JOIN Clarity..ZC_PHARM_SUBCLASS zc_subpharm ON med.PHARM_SUBCLASS_C = zc_subpharm.PHARM_SUBCLASS_C
LEFT JOIN CLARITY..ZC_SIMPLE_GENERIC zc_sg ON zc_sg.SIMPLE_GENERIC_C = med.SIMPLE_GENERIC_C
LEFT JOIN #rxnorm rxnorm ON rxnorm.MEDICATION_ID = ord_med.MEDICATION_ID
LEFT JOIN PAT_ENC enc ON enc.PAT_ENC_CSN_ID = ord_med.PAT_ENC_CSN_ID
WHERE ord_med.PAT_ENC_CSN_ID IN (
		SELECT DISTINCT PAT_ENC_CSN_ID
		FROM ##all_enc
		)

SELECT *
FROM #meds

-- Save to .csv file named: PDC_Medications.csv
