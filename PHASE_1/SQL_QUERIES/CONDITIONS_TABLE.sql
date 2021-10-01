DROP TABLE IF EXISTS #conditions
DROP TABLE IF EXISTS #diags

SELECT diags.CSN
      ,diags.START_DT
      ,diags.END_DT
      ,diags.DX_ID
      ,edg.DX_NAME
      ,diags.SOURCE
      ,edg.CURRENT_ICD10_LIST
	    ,diags.PRIMARY_YN
	into #diags
    FROM (SELECT
          dx.PAT_ENC_CSN_ID as CSN,
          dx.CONTACT_DATE as START_DT,
          dx.CONTACT_DATE as END_DT,
          dx.DX_ID as DX_ID,
		      NULLIF(dx.PRIMARY_DX_YN,'N') as PRIMARY_YN,
          'ENC_DX' as SOURCE
      FROM PAT_ENC_DX dx
      WHERE dx.PAT_ENC_CSN_ID IN (SELECT DISTINCT PAT_ENC_CSN_ID FROM ##all_enc) UNION ALL SELECT
        hp.PAT_ENC_CSN_ID as CSN,
        pl.NOTED_DATE as START_DT,
        pl.RESOLVED_DATE as END_DT,
        pl.DX_ID as DX_ID,
		    NULLIF(hp.PRINCIPAL_PROB_YN, 'N') as PRIMARY_YN,
		    'PROB_LIST' as SOURCE
      FROM PAT_ENC_HOSP_PROB hp
        LEFT JOIN PROBLEM_LIST pl on hp.PROBLEM_LIST_ID = pl.PROBLEM_LIST_ID
      WHERE hp.PAT_ENC_CSN_ID IN (SELECT DISTINCT PAT_ENC_CSN_ID FROM ##all_enc) UNION ALL SELECT
        pe.PAT_ENC_CSN_ID AS CSN,
        hsp.ADM_DATE_TIME AS START_DT,
        hsp.LAST_INTRM_BILL_DT AS END_DT,
        dx_list.DX_ID AS DX_ID,
		    NULL as PRIMARY_YN,
		    'BILLING' as SOURCE
      FROM PAT_ENC pe
        LEFT JOIN HSP_ACCOUNT hsp ON hsp.HSP_ACCOUNT_ID = pe.HSP_ACCOUNT_ID
        LEFT JOIN HSP_ACCT_DX_LIST dx_list ON dx_list.HSP_ACCOUNT_ID = pe.HSP_ACCOUNT_ID
      WHERE pe.PAT_ENC_CSN_ID IN (SELECT DISTINCT PAT_ENC_CSN_ID FROM ##all_enc) UNION ALL SELECT
        PAT_ENC_CSN_ID as CSN,
        ED_DISPOSITION_DTTM as START_DT,
        ED_DISPOSITION_DTTM as END_DT,
        PRIMARY_DX_ID as DX_ID,
		    NULLIF(PRIMARY_DX_ED_YN,'N') as PRIMARY_YN,
        'ED_PRIMARY' as SOURCE
      FROM F_ED_ENCOUNTERS
      WHERE PRIMARY_DX_ED_YN = 'Y'
        and PAT_ENC_CSN_ID IN (SELECT DISTINCT PAT_ENC_CSN_ID FROM ##all_enc)) diags
        LEFT JOIN CLARITY_EDG edg ON edg.DX_ID = diags.DX_ID
      WHERE diags.DX_ID IS NOT NULL
      GROUP BY
        diags.CSN, diags.START_DT, diags.END_DT,
        diags.DX_ID, edg.DX_NAME, diags.SOURCE,
        edg.CURRENT_ICD10_LIST, diags.PRIMARY_YN;

SELECT MIN(enc.PAT_ID) as pid
	,CSN as hid
	,MIN(enc.BIRTH_DATE) as BIRTH_DATE
	,START_DT as recorded
	,MIN(DATEDIFF(DAY, enc.BIRTH_DATE, START_DT)) AS recorded_Anonomyzied
	,MIN('ICD10') as nomenclature
	,MIN(dia.CURRENT_ICD10_LIST) as code
	,MIN(dia.DX_NAME) as codeText
	,MIN(dia.SOURCE) as source
	,MIN(START_DT) as onset
	,MIN(DATEDIFF(DAY, enc.BIRTH_DATE, START_DT)) AS onset_Anonomyzied
	,MIN(END_DT) as abatement
	,MIN(DATEDIFF(DAY, enc.BIRTH_DATE, END_DT)) AS abatement_Anonomyzied
	,CASE WHEN END_DT IS NOT NULL THEN '1' ELSE '0' END as abatementBoolean
	,MIN(dia.PRIMARY_YN) as isPrimary
INTO #conditions
FROM #diags dia
JOIN ##all_enc enc ON dia.CSN = enc.PAT_ENC_CSN_ID 
GROUP BY CSN, DX_ID, START_DT, END_DT

SELECT *
FROM #conditions

-- Save to .csv file named: PDC_CONDITIONS_TABLE.csv
