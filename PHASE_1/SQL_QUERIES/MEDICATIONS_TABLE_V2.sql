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

-- Write this out as 'medications.csv' file
SELECT DISTINCT *
FROM #meds


/*
 Medication Nomenclature Hierarcy 

 This large CTE query will extract many possible linkages for medications to standard
 nomenclatures. There are multiple places where these medications can be linked in the EHR, 
 and this CTE table will account for many of them. 

 In addition to the main medication IDs, there are three other places where medication
 IDs can be sourced from the principle ID - ingredients, components, or production drugs. 
 In addition, production drugs can also have separate ingredients. Each of these is a 
 1:many relationship.

 In this query, first we identify all of the possible medication IDs from these five 
 total sources. We will union them together and store them in the #med_hierarchy
 temporary table. This table should be saved out as the med_hierarchy CSV file.

 Then (in subsequent queries), we generate a distinct medication ID list, and 
 query all of the nomenclatures with this distinct list. Those will be saved
 out as the med_links CSV file. 
 */
DROP TABLE IF EXISTS #med_hierarchy;
WITH med AS (
  SELECT DISTINCT 
    med.medID 
	,NULL AS proxyMedID
	,NULL AS componentMedID
	,NULL AS productionMedID
	,NULL AS line
	,NULL AS componentType
  FROM (SELECT medID FROM #meds) med
),
/*
 * Next we identify all of the ingredients in these meds
 */
med_ingred AS (
  SELECT 
    med.medID as medID
    ,ingred.INGRED_ID AS proxyMedID
	,NULL AS componentMedID
	,NULL AS productionMedID
    ,ingred.LINE
	,NULL AS componentType
  FROM med
    INNER JOIN RX_MED_INGRED_ID ingred ON ingred.MEDICATION_ID = med.medID
),
/*
 * Next we identify all components in these meds, as well as the component type. 
 */
med_comp AS (
  SELECT
    med.medID AS medID
	,NULL AS proxyMedID
	,comp.DRUG_ID AS componentMedID
	,NULL AS productionMedID
	,comp.LINE
	,zc_type.NAME AS componentType
  FROM med
    INNER JOIN RX_MED_MIX_COMPON comp ON comp.MEDICATION_ID = med.medID
	LEFT JOIN ZC_INGRED_TYPE zc_type ON comp.TYPE_C = zc_type.DISP_CTYPE_C
),
/*
 * Next we select drug production medications
 */
med_prod AS (
  SELECT 
    med.medID AS medID
	,NULL AS proxyMedID
	,NULL AS componentMedID
	,prod.DRUG_PRODUCTION_ID AS productionMedID
	,prod.LINE
	,NULL AS componentType
  FROM med
    INNER JOIN DRUG_PRODUCTION prod ON prod.MEDICATION_ID = med.medID
),
/*
 * Some of the production drugs have components. We will recurse one level
 * on this query to pull components from production drug IDs 
 */
prod_comps AS (
  SELECT 
    med_prod.medID AS medID
	,NULL AS proxyMedID
	,comp.DRUG_ID AS componentMedID
	,med_prod.productionMedID
	,comp.LINE
	,zc_type.NAME AS componentType
  FROM med_prod
    INNER JOIN RX_MED_MIX_COMPON comp ON comp.MEDICATION_ID = med_prod.productionMedID
	LEFT JOIN ZC_INGRED_TYPE zc_type ON comp.TYPE_C = zc_type.DISP_CTYPE_C
), 
/* 
 * Some components have ingredients, which we will recurse onse to pull these IDs.
 */
comp_ingreds AS (
  SELECT 
    med_comp.medID as medID
    ,ingred.INGRED_ID AS proxyMedID
	,med_comp.componentMedID
	,NULL AS productionMedID
    ,ingred.LINE
	,med_comp.componentType
  FROM med_comp
    INNER JOIN RX_MED_INGRED_ID ingred ON ingred.MEDICATION_ID = med_comp.componentMedID
),
/*
 * Lastly, some of the ingredient drugs have ingredient drugs of their own. We will
 * recurse on this query once to pull ingredient drug IDs
 */
ingred_ingreds AS (
  SELECT 
    med_ingred.medID as medID
    ,ingred.INGRED_ID AS proxyMedID
	,NULL AS componentMedID
	,NULL AS productionMedID
    ,ingred.LINE
	,NULL AS componentType
  FROM med_ingred
    INNER JOIN RX_MED_INGRED_ID ingred ON ingred.MEDICATION_ID = med_ingred.proxyMedID
),
/*
 * Union all of these medication hierarchies together. This will be saved out as
 * the medication_heirarchy table.
 */
all_meds AS (
  SELECT * FROM med
  UNION ALL
  SELECT * FROM med_ingred
  UNION ALL
  SELECT * FROM med_comp
  UNION ALL
  SELECT * FROM med_prod
  UNION ALL
  SELECT * FROM prod_comps
  UNION ALL
  SELECT * FROM comp_ingreds
  UNION ALL 
  SELECT * FROM ingred_ingreds
)
SELECT DISTINCT *
INTO #med_hierarchy
FROM all_meds;

-- Write this out as 'med_hierarchy.csv' file
SELECT *
FROM #med_hierarchy
ORDER BY medID, proxyMedID, productionMedID, componentMedID;


/*
 Medication Linkage

 Now that we have a set of all possible medication IDs linked to the
 initial (principle) medication ID, we will identify linkages in the EHR
 to standard nomenclatures. 

 First we will generate a list of distinct medication IDs. From this
 distinct list, which is based on *all* of the above medication IDs 
 (and not just the original distinct principle medication IDs), 
 we will link to the heirarchies of interest.
*/
DROP TABLE IF EXISTS #med_links;
WITH 
all_med_ids_raw AS (
  SELECT DISTINCT medID AS MEDICATION_ID FROM #med_hierarchy
  UNION ALL
  SELECT DISTINCT proxyMedID AS MEDICATION_ID FROM #med_hierarchy
  UNION ALL 
  SELECT DISTINCT componentMedID AS MEDICATION_ID FROM #med_hierarchy
  UNION ALL 
  SELECT DISTINCT productionMedID AS MEDICATION_ID FROM #med_hierarchy
),
all_med_ids AS (
  SELECT DISTINCT MEDICATION_ID FROM all_med_ids_raw
),
/*
 * RXNORM
 * ======
 * First link to the RxNORM tables for all medication IDs.
 */
all_rxnorm AS (
  SELECT
    med.MEDICATION_ID AS medID
	,NULL AS line
	,'RXNORM' as nomenclature
	,CAST(rxnorm.RXNORM_CODE AS VARCHAR) AS code -- Force code to be VARCHAR
	,NULL AS name
	,zc_level.NAME AS rxNormCodeLevel
	,zc_type.NAME AS rxNormTermType
  FROM all_med_ids med
    INNER JOIN RXNORM_CODES rxnorm ON rxnorm.MEDICATION_ID = med.MEDICATION_ID
	LEFT JOIN ZC_RXNORM_CODE_LEVEL zc_level ON rxnorm.RXNORM_CODE_LEVEL_C = zc_level.RXNORM_CODE_LEVEL_C
	LEFT JOIN ZC_RXNORM_TERM_TYPE zc_type ON rxnorm.RXNORM_TERM_TYPE_C = zc_type.RXNORM_TERM_TYPE_C
),
/*
 * NDC
 * ===
 * Now we do the same with NDC links, which are found in the individual CLARITY_MEDICATION table
 */
all_ndc AS (
  SELECT 
    med.MEDICATION_ID AS medID
	,ndc.LINE AS line
	,'NDC' AS nomenclature
	,CAST(rx_ndc.RAW_NDC_CODE AS VARCHAR) AS code
	,ndc.NDC_CODE AS name
	,NULL AS rxNormCodeLevel
	,NULL AS rxNormTermType
  FROM all_med_ids med
    INNER JOIN CLARITY_NDC_CODES ndc ON ndc.MEDICATION_ID = med.MEDICATION_ID
	INNER JOIN RX_NDC rx_ndc ON rx_ndc.NDC_CODE = ndc.NDC_CODE
),
/* 
 * THERA CLASS
 * ===========
 * Write out the therapeutic class (I ERX 100) for this medication
 */
all_thera AS (
  SELECT
    med.MEDICATION_ID AS medID
	,NULL AS line
	,'THERA_CLASS' AS nomenclature
	,CAST(zc_thera.INTERNAL_ID AS VARCHAR) AS code
	,zc_thera.NAME AS name
	,NULL AS rxNormCodeLevel
	,NULL AS rxNormTermType
  FROM all_med_ids med
    INNER JOIN CLARITY_MEDICATION clar_med ON clar_med.MEDICATION_ID = med.MEDICATION_ID
	INNER JOIN ZC_THERA_CLASS zc_thera ON clar_med.THERA_CLASS_C = zc_thera.THERA_CLASS_C
),
/* 
 * PHARM CLASS
 * ===========
 * Write out the phmaraceuticala class (I ERX 110) for this medication
 */
all_pharm AS (
  SELECT
    med.MEDICATION_ID AS medID
	,NULL AS line
	,'PHARM_CLASS' AS nomenclature
	,CAST(zc_pharm.INTERNAL_ID AS VARCHAR) AS code
	,zc_pharm.NAME AS name
	,NULL AS rxNormCodeLevel
	,NULL AS rxNormTermType
  FROM all_med_ids med
    INNER JOIN CLARITY_MEDICATION clar_med ON clar_med.MEDICATION_ID = med.MEDICATION_ID
	INNER JOIN ZC_PHARM_CLASS zc_pharm ON clar_med.PHARM_CLASS_C = zc_pharm.PHARM_CLASS_C
),
/* 
 * PHARM SUB-CLASS
 * ===============
 * Write out the phmaraceuticala sub-class (I ERX 112) for this medication
 */
all_pharm_sub AS (
  SELECT
    med.MEDICATION_ID AS medID
	,NULL AS line
	,'PHARM_SUBCLASS' AS nomenclature
	,CAST(zc_pharm_sub.INTERNAL_ID AS VARCHAR) AS code
	,zc_pharm_sub.NAME AS name
	,NULL AS rxNormCodeLevel
	,NULL AS rxNormTermType
  FROM all_med_ids med
    INNER JOIN CLARITY_MEDICATION clar_med ON clar_med.MEDICATION_ID = med.MEDICATION_ID
	INNER JOIN ZC_PHARM_SUBCLASS zc_pharm_sub ON clar_med.PHARM_SUBCLASS_C = zc_pharm_sub.PHARM_SUBCLASS_C
),
/* 
 * SIMPLE GENERIC
 * ===============
 * Write out the simple generic categories (I ERX 114) for this medication
 */
all_sg AS (
  SELECT
    med.MEDICATION_ID AS medID
	,NULL AS line
	,'SIMPLE GENERIC' AS nomenclature
	,CAST(zc_sg.INTERNAL_ID AS VARCHAR) AS code
	,zc_sg.NAME AS name
	,NULL AS rxNormCodeLevel
	,NULL AS rxNormTermType
  FROM all_med_ids med
    INNER JOIN CLARITY_MEDICATION clar_med ON clar_med.MEDICATION_ID = med.MEDICATION_ID
	INNER JOIN ZC_SIMPLE_GENERIC zc_sg ON clar_med.SIMPLE_GENERIC_C = zc_sg.SIMPLE_GENERIC_C
),
/*
 * Union all link subtables into a single table
 */
all_links AS (
  SELECT DISTINCT * FROM all_rxnorm
  UNION ALL
  SELECT DISTINCT * FROM all_ndc
  UNION ALL
  SELECT DISTINCT * FROM all_thera
  UNION ALL 
  SELECT DISTINCT * FROM all_pharm
  UNION ALL
  SELECT DISTINCT * FROM all_pharm_sub
  UNION ALL 
  SELECT DISTINCT * FROM all_sg
)
SELECT DISTINCT * INTO #med_links FROM all_links;

-- Write this out as 'med_links.csv' file
SELECT *
FROM #med_links
ORDER BY nomenclature, medID, line;


/*
 TESTING
 =======

 Below we look for unique medication IDs for which there are NO existing
 linkage into the RxNORM dataset, either by the individual medication
 or by any of its sub-medications.

 To do this we first try to match the original (principle) medication ID to
 the #med_links table. For all unmatched original IDs, we look across
 the remaining med indices (ingredient, component, production) and try
 to find a match to #med_links table. 
*/

DROP TABLE IF EXISTS #med_test;
WITH
/* 
 Find the unique medication IDs from the patient's Meds dataset 
*/
unq_meds AS (
  SELECT DISTINCT medID
    ,med.NAME AS CLARITY_NAME
  FROM #meds
    LEFT JOIN CLARITY_MEDICATION med ON #meds.medID = med.MEDICATION_ID
),
/*
 Find the RxNORM matches to the principle medication IDs
 */
original_matches AS (
  SELECT 
    unq_meds.medID AS ORIG_MED_ID
	,unq_meds.CLARITY_NAME
	,NULL AS proxyMedID
	,NULL AS componentMedID
	,NULL AS productionMedID
    ,links.*
  FROM unq_meds
    LEFT JOIN #med_links links ON links.medID = unq_meds.medID AND links.nomenclature = 'RXNORM'
),
/*
 For the remaining (unmatched), look for ingredient matches 
 */
ingred_matches AS (
  SELECT
    unmatched.ORIG_MED_ID
	,unmatched.CLARITY_NAME
	,mh.proxyMedID
	,NULL AS componentMedID
	,NULL AS productionMedID
	,links.*
  FROM (SELECT DISTINCT ORIG_MED_ID, CLARITY_NAME FROM original_matches WHERE code IS NULL) AS unmatched
    INNER JOIN #med_hierarchy mh ON mh.medID = unmatched.ORIG_MED_ID AND mh.proxyMedID IS NOT NULL
    LEFT JOIN #med_links links ON links.medID = mh.proxyMedID AND links.nomenclature = 'RXNORM'
),
/* 
 For the remaining (unmatched), look for component matches
 */
comp_matches AS (
  SELECT 
    unmatched.ORIG_MED_ID
	,unmatched.CLARITY_NAME
	,NULL AS proxyMedID
	,mh.componentMedID
	,NULL AS productionMedID
	,links.*
  FROM (SELECT DISTINCT ORIG_MED_ID, CLARITY_NAME FROM original_matches WHERE code IS NULL) AS unmatched
    INNER JOIN #med_hierarchy mh ON mh.medID = unmatched.ORIG_MED_ID AND mh.componentMedID IS NOT NULL
	LEFT JOIN #med_links links ON links.medID = mh.componentMedID AND links.nomenclature = 'RXNORM'
),
/* 
 Lastly, for the remaining (unmatched), look for production matches
 */
prod_matches AS (
  SELECT 
    unmatched.ORIG_MED_ID
	,unmatched.CLARITY_NAME
	,NULL AS proxyMedID
	,NULL AS componentMedID
	,mh.productionMedID
	,links.*
  FROM (SELECT DISTINCT ORIG_MED_ID, CLARITY_NAME FROM original_matches WHERE code IS NULL) AS unmatched
    INNER JOIN #med_hierarchy mh ON mh.medID = unmatched.ORIG_MED_ID AND mh.productionMedID IS NOT NULL
	LEFT JOIN #med_links links ON links.medID = mh.productionMedID AND links.nomenclature = 'RXNORM'
),
/*
 Union all matches together into a single match table 
 */
all_matches AS (
  SELECT * FROM original_matches WHERE code IS NOT NULL
  UNION ALL 
  SELECT * FROM ingred_matches WHERE code IS NOT NULL
  UNION ALL
  SELECT * FROM comp_matches WHERE code IS NOT NULL
  UNION ALL 
  SELECT * FROM prod_matches WHERE code IS NOT NULL
)
SELECT * 
INTO #med_test
FROM all_matches;

-- Query for the unique principle Med IDs (and names) that do not have any link across all hierarchies
-- These can be examined in Record Viewer to see if there are other linkages that may apply
SELECT DISTINCT
  unq_meds.medID
  ,med.NAME AS CLARITY_NAME
FROM (SELECT DISTINCT medID FROM #meds) AS unq_meds
  LEFT JOIN CLARITY_MEDICATION med ON med.MEDICATION_ID = unq_meds.medID
  LEFT JOIN #med_test ON unq_meds.medID = #med_test.ORIG_MED_ID
WHERE code IS NULL;

-- What proportion of all medication orders do these (unmatched) med IDs account for?
SELECT 
  'All Unique Principle Med IDs' AS DESCRIP
  ,COUNT(*) AS CNT
FROM (SELECT DISTINCT medID FROM #meds) meds
UNION ALL
SELECT 
  'Unique Unmatched Principle Med IDs' AS DESCRIP
  ,COUNT(*) AS CNT
FROM (
  SELECT DISTINCT unq_meds.medID
  FROM (SELECT DISTINCT medID FROM #meds) AS unq_meds
    LEFT JOIN #med_test ON unq_meds.medID = #med_test.ORIG_MED_ID
  WHERE code IS NULL) med
UNION ALL
SELECT 
  'All Med Admins' AS DESCRIP
  ,COUNT(*) AS CNT
FROM #meds
UNION ALL
SELECT 
  'Unmatched Med Admins' AS DESCRIP
  ,COUNT(*) AS CNT
FROM #meds
WHERE medID IN (
  SELECT DISTINCT
    unq_meds.medID
  FROM (SELECT DISTINCT medID FROM #meds) AS unq_meds
    LEFT JOIN #med_test ON unq_meds.medID = #med_test.ORIG_MED_ID
  WHERE code IS NULL);