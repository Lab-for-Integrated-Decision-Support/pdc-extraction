DROP TABLE IF EXISTS #adt_entry
DROP TABLE IF EXISTS #adt_all_rows
DROP TABLE IF EXISTS #adt_remove_periop
DROP TABLE IF EXISTS #adt_same_dept
DROP TABLE IF EXISTS #adt_visit_dt_set
DROP TABLE IF EXISTS #adt_final_cohort
DROP TABLE IF EXISTS ##all_enc

-- Dates user wants full cohort to contain
DECLARE @startdate DATETIME = '01/01/2011'
		,@enddate DATETIME = '04/11/2021'

DECLARE @ICU TABLE (
	dpt_grp VARCHAR(50) -- User defined, must include PERIOP
	,dpt_id VARCHAR(25) -- EPIC Department IDs, found from helper queries
	,opendate DATE -- date department opened (if department doesn't have a distinct open date, please enter in @startdate from above) 
	,closedate DATE -- date department closed (if department doesn't have a distinct close date, please enter in @enddate from above)
	,displayName VARCHAR(150) NULL -- This is used just for ease of reading the code, this field is user defined and not used within the query. This should be an identifying name for he user to easily parse and remeber which department this row is for.
	)

-- 
INSERT INTO @ICU
VALUES (
	'PCICU'
	,'123456789'
	,'2011-01-01'
	,'2017-10-01'
	,'4-2800'
	)
	,(
	'PERIOP'
	,'987654321'
	,'2011-01-01'
	,'2021-04-11'
	,'CHGI'
	)

SELECT adt.EVENT_ID
	,adt.PAT_ENC_CSN_ID
	,adt.PAT_ID
	,adt.EFFECTIVE_TIME
	,adt.EVENT_TIME
	,adt.SEQ_NUM_IN_ENC
	,zc_et.NAME AS EVENT_TYPE
	,zc_est.NAME AS EVENT_SUB_TYPE
	,dep.DEPARTMENT_NAME
	,dep.DEPARTMENT_ID
	,room.ROOM_NAME
	,zc_pc.NAME AS PAT_CLASS
	,adt.XFER_IN_EVENT_ID
	,adt.NEXT_OUT_EVENT_ID
	,adt.LAST_IN_EVENT_ID
	,adt.PREV_EVENT_ID
INTO #adt_entry
FROM CLARITY_ADT adt
LEFT JOIN ZC_EVENT_TYPE zc_et ON zc_et.EVENT_TYPE_C = adt.EVENT_TYPE_C
LEFT JOIN ZC_EVENT_SUBTYPE zc_est ON zc_est.EVENT_SUBTYPE_C = adt.EVENT_SUBTYPE_C
LEFT JOIN CLARITY_DEP dep ON dep.DEPARTMENT_ID = adt.DEPARTMENT_ID
LEFT JOIN ED_ROOM_INFO room ON room.ROOM_ID = adt.ROOM_ID
LEFT JOIN ZC_PAT_CLASS zc_pc ON zc_pc.ADT_PAT_CLASS_C = adt.PAT_CLASS_C
INNER JOIN @ICU icu ON adt.DEPARTMENT_ID = icu.dpt_id
	AND icu.dpt_grp <> 'PERIOP'
	AND adt.EFFECTIVE_TIME > icu.opendate
	AND adt.EFFECTIVE_TIME < icu.closedate
WHERE zc_et.NAME IN (
		'Admission'
		,'Transfer In'
		)
	AND adt.EFFECTIVE_TIME > @startdate --'01/01/2011'
	AND adt.EFFECTIVE_TIME < @enddate --'04/11/2021'
	AND zc_est.NAME NOT IN ('Canceled');-- Yes, it's spelled incorrectly

SELECT DISTINCT adt.EVENT_ID
	,adt.PAT_ENC_CSN_ID
	,adt.PAT_ID
	,pat.PAT_LAST_NAME
	,pat.PAT_FIRST_NAME
	,pat.PAT_MRN_ID
	,pat.BIRTH_DATE
	,adt.EFFECTIVE_TIME
	,adt.EVENT_TIME
	,adt.SEQ_NUM_IN_ENC
	,zc_et.NAME AS EVENT_TYPE
	,CASE 
		WHEN zc_et.NAME IN (
				'Admission'
				,'Transfer In'
				)
			THEN 'In'
		WHEN zc_et.NAME IN (
				'Transfer Out'
				,'Discharge'
				)
			THEN 'Out'
		END AS EVENT_DIR
	,zc_est.NAME AS EVENT_SUB_TYPE
	,dep.DEPARTMENT_NAME
	,dep.DEPARTMENT_ID
	,COALESCE(icu.dpt_grp, 'OTHER') AS DEPT_GRP
	,room.ROOM_NAME
INTO #adt_all_rows
FROM #adt_entry
LEFT JOIN CLARITY_ADT adt ON #adt_entry.PAT_ENC_CSN_ID = adt.PAT_ENC_CSN_ID
LEFT JOIN PATIENT pat ON adt.PAT_ID = pat.PAT_ID
LEFT JOIN ZC_EVENT_TYPE zc_et ON zc_et.EVENT_TYPE_C = adt.EVENT_TYPE_C
LEFT JOIN ZC_EVENT_SUBTYPE zc_est ON zc_est.EVENT_SUBTYPE_C = adt.EVENT_SUBTYPE_C
LEFT JOIN CLARITY_DEP dep ON dep.DEPARTMENT_ID = adt.DEPARTMENT_ID
LEFT JOIN ED_ROOM_INFO room ON room.ROOM_ID = adt.ROOM_ID
LEFT JOIN @ICU icu ON adt.DEPARTMENT_ID = icu.dpt_id
WHERE zc_et.NAME IN (
		'Admission'
		,'Transfer In'
		,'Transfer Out'
		,'Discharge'
		)
	AND zc_est.NAME NOT IN ('Canceled')
ORDER BY PAT_ENC_CSN_ID
	,SEQ_NUM_IN_ENC;

SELECT *
	,FIRST_VALUE(EFFECTIVE_TIME) OVER (
		PARTITION BY PAT_ENC_CSN_ID ORDER BY SEQ_NUM_IN_ENC
		) AS HOSP_ADMIT_DT
	,FIRST_VALUE(EFFECTIVE_TIME) OVER (
		PARTITION BY PAT_ENC_CSN_ID ORDER BY SEQ_NUM_IN_ENC DESC
		) AS HOSP_DC_DT
	,CASE 
		WHEN (
				LAG(DEPT_GRP) OVER (
					PARTITION BY PAT_ENC_CSN_ID ORDER BY SEQ_NUM_IN_ENC
						,EVENT_DIR
					) IN ('PERIOP')
				AND DEPT_GRP IN ('PERIOP')
				AND LAG(EVENT_TYPE) OVER (
					PARTITION BY PAT_ENC_CSN_ID ORDER BY SEQ_NUM_IN_ENC
						,EVENT_DIR
					) IN (
					'Admission'
					,'Transfer In'
					)
				AND EVENT_TYPE IN (
					'Discharge'
					,'Transfer Out'
					)
				)
			OR (
				LEAD(DEPT_GRP) OVER (
					PARTITION BY PAT_ENC_CSN_ID ORDER BY SEQ_NUM_IN_ENC
						,EVENT_DIR
					) IN ('PERIOP')
				AND DEPT_GRP IN ('PERIOP')
				AND LEAD(EVENT_TYPE) OVER (
					PARTITION BY PAT_ENC_CSN_ID ORDER BY SEQ_NUM_IN_ENC
						,EVENT_DIR
					) IN (
					'Transfer Out'
					,'Discharge'
					)
				AND EVENT_TYPE IN (
					'Admission'
					,'Transfer In'
					)
				)
			THEN 'YES'
		END AS OUT_PERIOP
INTO #adt_remove_periop
FROM #adt_all_rows
ORDER BY PAT_ENC_CSN_ID
	,SEQ_NUM_IN_ENC
	,EVENT_DIR;

SELECT *
	,CASE 
		WHEN LAG(DEPT_GRP) OVER (
				PARTITION BY PAT_ENC_CSN_ID ORDER BY SEQ_NUM_IN_ENC
					,EVENT_DIR
				) IN (DEPT_GRP)
			THEN 'YES'
		END AS SAME_DEPT
INTO #adt_same_dept
FROM #adt_remove_periop
WHERE OUT_PERIOP IS NULL
ORDER BY PAT_ENC_CSN_ID
	,SEQ_NUM_IN_ENC
	,EVENT_DIR;

SELECT *
	,CASE 
		WHEN SAME_DEPT IS NULL
			THEN EFFECTIVE_TIME
		END AS VISIT_IN_DT
	,CASE 
		WHEN LEAD(SAME_DEPT) OVER (
				PARTITION BY PAT_ENC_CSN_ID ORDER BY SEQ_NUM_IN_ENC
					,EVENT_DIR
				) IS NULL
			THEN EFFECTIVE_TIME
		END AS VISIT_OUT_DT
INTO #adt_visit_dt_set
FROM #adt_same_dept
WHERE DEPT_GRP NOT IN (
		'PERIOP'
		,'OTHER'
		)
ORDER BY PAT_ENC_CSN_ID
	,SEQ_NUM_IN_ENC
	,EVENT_DIR;

SELECT DISTINCT vtdt.*
	,CASE 
		WHEN VISIT_OUT_DT IS NULL
			THEN LEAD(VISIT_OUT_DT) OVER (
					PARTITION BY vtdt.PAT_ENC_CSN_ID ORDER BY SEQ_NUM_IN_ENC
						,EVENT_DIR
					)
		END AS OUT_DT
	,YEAR(VISIT_IN_DT) AS IN_YEAR
	,enc.DISCH_DISP_C
	,p.SEX_C
INTO #adt_final_cohort
FROM #adt_visit_dt_set vtdt
LEFT JOIN PAT_ENC_HSP enc ON vtdt.PAT_ENC_CSN_ID = enc.PAT_ENC_CSN_ID
LEFT JOIN PATIENT p ON vtdt.PAT_ID = p.PAT_ID
WHERE VISIT_IN_DT IS NOT NULL
	OR VISIT_OUT_DT IS NOT NULL
ORDER BY vtdt.PAT_ENC_CSN_ID
	,SEQ_NUM_IN_ENC
	,EVENT_DIR;

SELECT EVENT_ID
	,PAT_ENC_CSN_ID
	,PAT_ID
	,PAT_MRN_ID -- Needed for VPS
	,PAT_LAST_NAME -- Needed for VPS
	,PAT_FIRST_NAME -- Needed for VPS
	,BIRTH_DATE
	,EFFECTIVE_TIME
	,EVENT_TIME
	,EVENT_TYPE
	,DEPARTMENT_NAME
	,DEPT_GRP
	,ROOM_NAME AS FIRST_ROOM_NAME
	,HOSP_ADMIT_DT
	,HOSP_DC_DT
	,VISIT_IN_DT AS ICU_IN_DT
	,OUT_DT AS ICU_OUT_DT
	,IN_YEAR
	,DATEDIFF(MINUTE, VISIT_IN_DT, OUT_DT) / (60.) AS ICU_LOS_HRS
	,zc_disch.NAME AS DISCH_DISP
	,zc_disch.DISCH_DISP_C
	,zc_sex.NAME AS SEX
INTO ##all_enc
FROM #adt_final_cohort fcoh
LEFT JOIN ZC_DISCH_DISP zc_disch ON zc_disch.DISCH_DISP_C = fcoh.DISCH_DISP_C
LEFT JOIN ZC_SEX zc_sex ON fcoh.SEX_C = zc_sex.RCPT_MEM_SEX_C
WHERE VISIT_IN_DT IS NOT NULL
	AND OUT_DT IS NOT NULL
ORDER BY PAT_ENC_CSN_ID
	,SEQ_NUM_IN_ENC
	,EVENT_DIR;

SELECT *
FROM ##all_enc

-- Save to .csv file named: PDC_All_Encounters.csv
