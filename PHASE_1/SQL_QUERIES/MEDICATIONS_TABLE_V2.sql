/**
 Medication Table (v2)
 
 2022-02-05 This table now follows the format proposed to the PDC on 2022-02-11
   which will allow for consistent calculation of CMI and intermittent medications
   from individual sites. 

 It is written in MSSQL variant, and makes use of an ##all_encounters temporary (session)
 table to gather the unique CSNs of interest. Note that any base table can be used
 in place of this temporary table, and should be joined appropriately within the join 
 section. 

 The query is broken into sections corresponding to the color codes on the reference table,
 which was presented on 2022-02-11. 

 Deprecated columns and joins are included and commented out of this code. 
 */
DROP TABLE IF EXISTS #meds;
SELECT 
    --enc.PAT_ID AS pid 
	ord_med.PAT_ID AS pid -- Note this will be anonymized to PID
    ,ord_med.PAT_ENC_CSN_ID AS hid -- Note this will be anonymized to HID
	-- Medication informatino
	,dispense_med.MEDICATION_ID AS medID
	,mar.ORDER_MED_ID AS orderMedID
	,dispense_med.NAME AS medName
	,ord_med.DISPLAY_NAME
	-- Administration start and event time
	,mar.TAKEN_TIME AS startTime
	,mar.SAVED_TIME AS eventTime
	-- Route
	,zc_adm_rt.NAME AS route
	, zc_adm_rt.INTERNAL_ID AS routeCode
	-- Dose
	,mar.SIG AS doseQuantity
	,zc_unit.NAME AS quantityUnits
	,zc_unit.INTERNAL_ID AS quantityUnitCode
    -- Dose Rate
	,mar.INFUSION_RATE AS doseRate
	,zc_inf_unit.NAME AS rateUnits
	,zc_inf_unit.INTERNAL_ID AS rateUnitCode
	--- Duration
	,mar.MAR_DURATION AS duration
	,zc_dur_un.NAME AS durationUnit
	,zc_dur_un.INTERNAL_ID AS durationUnitCode
    -- MAR Action
	,zc_mar_rslt.NAME AS marAction
	,zc_mar_rslt.INTERNAL_ID AS marActionCode
    -- - - - - - - - - - - - -
	-- Deprecated 2022-02-04
    -- - - - - - - - - - - - -
	--,med.ROUTE AS MED_ROUTE
	--,zc_mar_rsn.NAME AS MAR_REASON
	--,dep.DEPARTMENT_NAME AS MED_ADMIN_DEPT_NAME
	--,zc_ord_stat.NAME AS ORDER_STATUS
	--,med.NAME AS MED_NAME
	--,zc_thera.NAME AS THERA_CLASS
	--,zc_pharm.NAME AS PHARM_CLASS
	--,zc_subpharm.NAME AS PHARM_SUBCLASS
	--,zc_sg.NAME AS SIMPLE_GENERIC
	--,COALESCE(rxnorm.rxnormcode, ord_med.MEDICATION_ID) AS code
	--,COALESCE(rxnorm.nomenclature, 'MEDICATION ID') AS nomenclature
INTO #meds
FROM Clarity..MAR_ADMIN_INFO mar
LEFT JOIN Clarity..ORDER_MED ord_med ON ord_med.ORDER_MED_ID = mar.ORDER_MED_ID
LEFT JOIN Clarity..ZC_MAR_RSLT zc_mar_rslt ON mar.MAR_ACTION_C = zc_mar_rslt.RESULT_C
LEFT JOIN Clarity..ZC_ADMIN_ROUTE zc_adm_rt ON mar.ROUTE_C = zc_adm_rt.MED_ROUTE_C
LEFT JOIN Clarity..ZC_MED_UNIT zc_inf_unit ON mar.MAR_INF_RATE_UNIT_C = zc_inf_unit.DISP_QTYUNIT_C
LEFT JOIN Clarity..ZC_MED_UNIT zc_unit ON mar.DOSE_UNIT_C = zc_unit.DISP_QTYUNIT_C
LEFT JOIN Clarity..ZC_MED_DURATION_UN zc_dur_un ON mar.MAR_DURATION_UNIT_C = zc_dur_un.MED_DURATION_UN_C
LEFT JOIN Clarity..ORDER_MEDINFO ord_med_info ON ord_med.ORDER_MED_ID = ord_med_info.ORDER_MED_ID
LEFT JOIN Clarity..CLARITY_MEDICATION dispense_med ON ord_med_info.DISPENSABLE_MED_ID = dispense_med.MEDICATION_ID
-- Deprecated 2022-02-04
--LEFT JOIN Clarity..ZC_MAR_TIME_SRC zc_time_src ON mar.MAR_TIME_SOURCE_C = zc_time_src.MAR_TIME_SRC_C
--LEFT JOIN Clarity..ZC_MAR_RSN zc_mar_rsn ON mar.REASON_C = zc_mar_rsn.REASON_C
--LEFT JOIN Clarity..CLARITY_DEP dep ON mar.MAR_ADMIN_DEPT_ID = dep.DEPARTMENT_ID
--LEFT JOIN Clarity..ZC_ORDER_STATUS zc_ord_stat ON ord_med.ORDER_STATUS_C = zc_ord_stat.ORDER_STATUS_C
--LEFT JOIN Clarity..ZC_THERA_CLASS zc_thera ON med.THERA_CLASS_C = zc_thera.THERA_CLASS_C
--LEFT JOIN Clarity..ZC_PHARM_CLASS zc_pharm ON med.PHARM_CLASS_C = zc_pharm.PHARM_CLASS_C
--LEFT JOIN Clarity..ZC_PHARM_SUBCLASS zc_subpharm ON med.PHARM_SUBCLASS_C = zc_subpharm.PHARM_SUBCLASS_C
--LEFT JOIN CLARITY..ZC_SIMPLE_GENERIC zc_sg ON zc_sg.SIMPLE_GENERIC_C = med.SIMPLE_GENERIC_C
--LEFT JOIN PAT_ENC enc ON enc.PAT_ENC_CSN_ID = ord_med.PAT_ENC_CSN_ID
--LEFT JOIN PATIENT pat ON enc.PAT_ID = pat.PAT_ID
WHERE ord_med.PAT_ENC_CSN_ID IN (
  SELECT DISTINCT PAT_ENC_CSN_ID
  FROM ##all_enc
  );

SELECT TOP 1000 *
FROM #meds


/*
 Medication Nomenclature Linkage

 This large CTE query will extract many possible linkages for medications to standard
 nomenclatures. There are multiple places where these medications can be linked in the EHR, 
 and this CTE table will account for many of them. 

 In addition to the main medication IDs, there are three other places where medication
 IDs can be sourced from the principle ID - ingredients, components, or production drugs. 
 In addition, production drugs can also have separate ingredients. Each of these is a 
 1:many relationship.

 In this query, first we identify all of the possible medication IDs from these five 
 total sources.

 Then with this distinct medication ID list, we query all of the nomenclatures. 

 Lastly, we join back to the links between the principle ID and its sub-IDs. 
 */
DROP TABLE IF EXISTS #med_links;
WITH med AS (
  --SELECT med.MEDICATION_ID 
  --FROM CLARITY_MEDICATION med 
  --WHERE med.MEDICATION_ID IN (
    SELECT DISTINCT med.medID AS MEDICATION_ID
    FROM (SELECT medID FROM #meds) med
  --)
),
/*
 * Next we identify all of the ingredients in these meds, and filter for those which are not NULL.
 */
med_ingred AS (
  SELECT 
    med.MEDICATION_ID
    ,ingred.INGRED_ID AS proxyMedID
    ,ingred.LINE
  FROM med
    INNER JOIN RX_MED_INGRED_ID ingred ON ingred.MEDICATION_ID = med.MEDICATION_ID
  --WHERE ingred.INGRED_ID IS NOT NULL
),
/*
 * Next we identify all components in these meds, as well as the component type. We filter
 * for those which are not NULL.
 */
med_comp AS (
  SELECT
    med.MEDICATION_ID
	,comp.DRUG_ID AS componentMedID
	,comp.LINE
	,zc_type.NAME AS componentType
  FROM med
    INNER JOIN RX_MED_MIX_COMPON comp ON comp.MEDICATION_ID = med.MEDICATION_ID
	LEFT JOIN ZC_INGRED_TYPE zc_type ON comp.TYPE_C = zc_type.DISP_CTYPE_C
  --WHERE comp.DRUG_ID IS NOT NULL
),
/*
 * Next we select drug production medications and filter for those not null
 */
med_prod AS (
  SELECT 
    med.MEDICATION_ID
	,prod.DRUG_PRODUCTION_ID AS productionMedID
	,prod.LINE
  FROM med
    INNER JOIN DRUG_PRODUCTION prod ON prod.MEDICATION_ID = med.MEDICATION_ID
  --WHERE prod.DRUG_PRODUCTION_ID IS NOT NULL
),
/*
 * Some of the production drugs have components. We will recurse one level
 * on this query to pull components from production drug IDs 
 */
prod_comps AS (
  SELECT 
    med_prod.MEDICATION_ID
    ,med_prod.productionMedID
	,comp.DRUG_ID AS componentMedID
	,comp.LINE
	,zc_type.NAME AS componentType
  FROM med_prod
    INNER JOIN RX_MED_MIX_COMPON comp ON comp.MEDICATION_ID = med_prod.productionMedID
	LEFT JOIN ZC_INGRED_TYPE zc_type ON comp.TYPE_C = zc_type.DISP_CTYPE_C
  --WHERE comp.DRUG_ID IS NOT NULL
), 
/*
 * Union all of the medication IDs together and pull the distinct values
 * from this union. This unique list of med_ids will be used to gather
 * all of the nomenclature links.
 */
all_med_ids_raw AS (
  SELECT med.MEDICATION_ID AS MEDICATION_ID FROM med
  UNION ALL
  SELECT med_ingred.proxyMedID AS MEDICATION_ID FROM med_ingred
  UNION ALL
  SELECT med_comp.componentMedID AS MEDICATION_ID FROM med_comp
  UNION ALL
  SELECT med_prod.productionMedID AS MEDICATION_ID FROM med_prod
  UNION ALL
  SELECT prod_comps.componentMedID AS MEDICATION_ID FROM prod_comps
),
all_med_ids AS (
  SELECT DISTINCT MEDICATION_ID
  FROM all_med_ids_raw
),
/*
 * RXNORM
 * ======
 *
 * First link to the RxNORM tables for all medication IDs.
 */
all_rxnorm AS (
  SELECT
    med.MEDICATION_ID
	,NULL AS proxyMedID
	,NULL AS componentMedID
	,NULL AS productionMedID
	,NULL AS LINE
	,NULL AS componentType
	,rxnorm.RXNORM_CODE AS code
	,zc_level.NAME AS rxNormCodeLevel
	,zc_type.NAME AS rxNormTermType
  FROM all_med_ids med
    INNER JOIN RXNORM_CODES rxnorm ON rxnorm.MEDICATION_ID = med.MEDICATION_ID
	LEFT JOIN ZC_RXNORM_CODE_LEVEL zc_level ON rxnorm.RXNORM_CODE_LEVEL_C = zc_level.RXNORM_CODE_LEVEL_C
	LEFT JOIN ZC_RXNORM_TERM_TYPE zc_type ON rxnorm.RXNORM_TERM_TYPE_C = zc_type.RXNORM_TERM_TYPE_C
  --WHERE rxnorm.RXNORM_CODE IS NOT NULL
),
/* Now we will link proxy Meds (ingredients) to RXNORM */
ingred_rx AS (
  SELECT
    med_ingred.MEDICATION_ID
	,med_ingred.proxyMedID
	,NULL AS componentMedID
	,NULL AS productionMedID
	,med_ingred.LINE
	,NULL AS componentType
	,rxnorm.RXNORM_CODE AS code
	,zc_level.NAME AS rxNormCodeLevel
	,zc_type.NAME AS rxNormTermType
  FROM med_ingred
    LEFT JOIN RXNORM_CODES rxnorm ON rxnorm.MEDICATION_ID = med_ingred.proxyMedID
	LEFT JOIN ZC_RXNORM_CODE_LEVEL zc_level ON rxnorm.RXNORM_CODE_LEVEL_C = zc_level.RXNORM_CODE_LEVEL_C
	LEFT JOIN ZC_RXNORM_TERM_TYPE zc_type ON rxnorm.RXNORM_TERM_TYPE_C = zc_type.RXNORM_TERM_TYPE_C
  WHERE rxnorm.RXNORM_CODE IS NOT NULL
),
/* Now we will link component Meds to RXNORM */
comp_rx AS (
  SELECT
    med_comp.MEDICATION_ID
	,NULL AS proxyMedID
	,med_comp.componentMedID
	,NULL AS productionMedID
	,med_comp.LINE
	,med_comp.componentType
	,rxnorm.RXNORM_CODE AS code
	,zc_level.NAME AS rxNormCodeLevel
	,zc_type.NAME AS rxNormTermType
  FROM med_comp
    LEFT JOIN RXNORM_CODES rxnorm ON rxnorm.MEDICATION_ID = med_comp.componentMedID
	LEFT JOIN ZC_RXNORM_CODE_LEVEL zc_level ON rxnorm.RXNORM_CODE_LEVEL_C = zc_level.RXNORM_CODE_LEVEL_C
	LEFT JOIN ZC_RXNORM_TERM_TYPE zc_type ON rxnorm.RXNORM_TERM_TYPE_C = zc_type.RXNORM_TERM_TYPE_C
  WHERE rxnorm.RXNORM_CODE IS NOT NULL
),
/* Now we will link production Meds to RXNORM */
prod_rx AS (
  SELECT
    med_prod.MEDICATION_ID
	,NULL AS proxyMedID
	,NULL AS componentMedID
	,med_prod.productionMedID
	,med_prod.LINE
	,NULL AS componentType
	,rxnorm.RXNORM_CODE AS code
	,zc_level.NAME AS rxNormCodeLevel
	,zc_type.NAME AS rxNormTermType
  FROM med_prod
    LEFT JOIN RXNORM_CODES rxnorm ON rxnorm.MEDICATION_ID = med_prod.productionMedID
	LEFT JOIN ZC_RXNORM_CODE_LEVEL zc_level ON rxnorm.RXNORM_CODE_LEVEL_C = zc_level.RXNORM_CODE_LEVEL_C
	LEFT JOIN ZC_RXNORM_TERM_TYPE zc_type ON rxnorm.RXNORM_TERM_TYPE_C = zc_type.RXNORM_TERM_TYPE_C
  WHERE rxnorm.RXNORM_CODE IS NOT NULL
),
/* And lastly, link production component Meds to RXNORM */
prod_comp_rx AS (
  SELECT
    prod_comps.MEDICATION_ID
	,NULL AS proxyMedID
	,prod_comps.componentMedID
	,prod_comps.productionMedID
	,prod_comps.LINE
	,prod_comps.componentType
	,rxnorm.RXNORM_CODE AS code
	,zc_level.NAME AS rxNormCodeLevel
	,zc_type.NAME AS rxNormTermType
  FROM prod_comps
    LEFT JOIN RXNORM_CODES rxnorm ON rxnorm.MEDICATION_ID = prod_comps.componentMedID
	LEFT JOIN ZC_RXNORM_CODE_LEVEL zc_level ON rxnorm.RXNORM_CODE_LEVEL_C = zc_level.RXNORM_CODE_LEVEL_C
	LEFT JOIN ZC_RXNORM_TERM_TYPE zc_type ON rxnorm.RXNORM_TERM_TYPE_C = zc_type.RXNORM_TERM_TYPE_C
  WHERE rxnorm.RXNORM_CODE IS NOT NULL
),
/* Union together all RXNORM into a single table */
all_rx_raw AS (
  SELECT * FROM med_rx
  UNION ALL 
  SELECT * FROM ingred_rx
  UNION ALL
  SELECT * FROM comp_rx
  UNION ALL
  SELECT * FROM prod_rx
  UNION ALL
  SELECT * FROM prod_comp_rx
),
all_rx AS (
  SELECT DISTINCT
    MEDICATION_ID AS medID
	,proxyMedID
	,componentMedID
	,productionMedID
	,line
	,componentType
	,'RXNORM' AS nomenclature
	,code
	,NULL AS name
	,rxNormCodeLevel
	,rxNormTermType
  FROM all_rx_raw
),
/*
 * Now we do the same with NDC links, which are found in the individual CLARITY_MEDICATION table
 *
 * NDC
 * ===
 */
med_ndc AS (
  SELECT 
    med.MEDICATION_ID
	,NULL AS proxyMedID
	,NULL AS componentMedID
	,NULL AS productionMedID
	,ndc.LINE
	,NULL AS componentType
	,ndc.NDC_CODE AS code
  FROM med
    LEFT JOIN CLARITY_NDC_CODES ndc ON ndc.MEDICATION_ID = med.MEDICATION_ID
  WHERE ndc.NDC_CODE IS NOT NULL
),
/* Now do the same for ingredient medications */
ingred_ndc AS (
  SELECT 
    med_ingred.MEDICATION_ID
	,med_ingred.proxyMedID
	,NULL AS componentMedID
	,NULL AS productionMedID
	,ndc.LINE
	,NULL AS componentType
	,ndc.NDC_CODE AS code
  FROM med_ingred
    LEFT JOIN CLARITY_NDC_CODES ndc ON ndc.MEDICATION_ID = med_ingred.proxyMedID
  WHERE ndc.NDC_CODE IS NOT NULL
),
/** And for component medications */
comp_ndc AS (
  SELECT 
    med_comp.MEDICATION_ID
	,NULL AS proxyMedID
	,med_comp.componentMedID
	,NULL AS productionMedID
	,ndc.LINE
	,med_comp.componentType
	,ndc.NDC_CODE AS code
  FROM med_comp
    LEFT JOIN CLARITY_NDC_CODES ndc ON ndc.MEDICATION_ID = med_comp.componentMedID
  WHERE ndc.NDC_CODE IS NOT NULL
),
/** And for production medications */
prod_ndc AS (
  SELECT 
    med_prod.MEDICATION_ID
	,NULL AS proxyMedID
	,NULL AS componentMedID
	,med_prod.productionMedID
	,ndc.LINE
	,NULL AS componentType
	,ndc.NDC_CODE AS code
  FROM med_prod
    LEFT JOIN CLARITY_NDC_CODES ndc ON ndc.MEDICATION_ID = med_prod.productionMedID
  WHERE ndc.NDC_CODE IS NOT NULL
),
/** And lastly for production component medications */
prod_comp_ndc AS (
  SELECT 
    prod_comps.MEDICATION_ID
	,NULL AS proxyMedID
	,prod_comps.componentMedID
	,prod_comps.productionMedID
	,ndc.LINE
	,prod_comps.componentType
	,ndc.NDC_CODE AS code
  FROM prod_comps
    LEFT JOIN CLARITY_NDC_CODES ndc ON ndc.MEDICATION_ID = prod_comps.componentMedID
  WHERE ndc.NDC_CODE IS NOT NULL
),
/* UNION ALL NDC together and add NULL columns */
all_ndc_raw AS (
  SELECT * FROM med_ndc
  UNION ALL
  SELECT * FROM ingred_ndc
  UNION ALL
  SELECT * FROM comp_ndc
  UNION ALL
  SELECT * FROM prod_ndc
  UNION ALL
  SELECT * FROM prod_comp_ndc
),
all_ndc AS (
  SELECT DISTINCT 
    MEDICATION_ID AS medID
	,proxyMedID
	,componentMedID
	,productionMedID
	,line
	,componentType
	,'NDC' AS nomenclature
	,code
	,NULL AS name
	,NULL as rxNormCodeLevel
	,NULL AS rxNormTermType
  FROM all_ndc_raw
),
all_links AS (
  SELECT * FROM all_ndc 
  UNION ALL 
  SELECT * FROM all_rx
)
SELECT * 
INTO #med_links
FROM all_links;

/*
  ,'THERA_CLASS' AS nomenclature
  ,zc_thera.INTERNAL_ID AS code
  ,zc_thera.NAME
  ,NULL AS rxNormCodeLevel
  ,NULL AS rxNormTermType
FROM CLARITY_MEDICATION med
  LEFT JOIN CLARITY_MEDICATION proxy_med ON ingred.INGRED_ID = proxy_med.MEDICATION_ID
  LEFT JOIN ZC_THERA_CLASS zc_thera ON proxy_med.THERA_CLASS_C = zc_thera.THERA_CLASS_C
*/

/* Find the unique medication IDs from the patient's Meds dataset */
DROP TABLE IF EXISTS #unqmeds;
SELECT DISTINCT medID
INTO #unqmeds
FROM #meds;

/*
 Find the medication IDs which do not have any matches in the RXNORM dataset
 */
SELECT 
  #unqmeds.medID
  ,med.NAME
  ,links.*
FROM #unqmeds
  LEFT JOIN CLARITY_MEDICATION med ON med.MEDICATION_ID = #unqmeds.medID
  LEFT JOIN #med_links links ON links.medID = #unqmeds.medID AND links.nomenclature = 'RXNORM'
WHERE links.code IS NULL
ORDER BY #unqmeds.medID;