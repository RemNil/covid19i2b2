
--************************************************************
--************************************************************
--*** Precompute a few things for performance
--************************************************************
--************************************************************

--------------------------------------------------------------
-- Create the list of COVID-19 positive patients
-- * Customize for your local codes.
--------------------------------------------------------------
create table covid_pos_patients (
  patient_num, covid_pos_date,
  primary key (patient_num)
)
as select patient_num, cast(min(trunc(start_date)) as date) covid_pos_date
from nightherondata.observation_fact obs
where obs.concept_cd in (
 'KUH|COMPONENT_ID:6551', --	COVID-19 (SARS-COV-2) PCR SOURCE
 'KUH|COMPONENT_ID:6552' --	COVID-19 (SARS-COV-2) PCR
-- 'KUH|COMPONENT_ID:3523', --	CORONAVIRUS BL
-- 'KUH|COMPONENT_ID:3527' --	CORONAVIRUS NW
/*
 select 'KUH|COMPONENT_ID:' || cc.component_id as concept_cd, name
 from clarity.clarity_component cc
 where name in ('CORONAVIRUS BL', 'CORONAVIRUS NW')
 or lower(name) like '%covid%'
*/
)
and lower(tval_char) in ('detected', 'dectected')
-- and start_date >= date '2020-01-01'
	group by patient_num
;
-- select * from covid_pos_patients order by covid_pos_date;

--------------------------------------------------------------
-- Create a list of dates since the first case
--------------------------------------------------------------
create table date_list (d, primary key(d)) as
with n as (
	select 0 n from dual union all
    select 1 from dual union all
    select 2 from dual union all
    select 3 from dual union all
    select 4 from dual union all
    select 5 from dual union all
    select 6 from dual union all
    select 7 from dual union all
    select 8 from dual union all
    select 9 from dual
)
, delta as (
    select a.n + 10 * b.n + 100 * c.n as days
    from n a cross join n b cross join n c
)
, p as (
    select min(trunc(covid_pos_date)) s
    from covid_pos_patients
)
select p.s + delta.days as d
from p cross join delta
where p.s + delta.days <= current_date
order by 1
;


--------------------------------------------------------------
-- Create a list of dates when patients were in the ICU
-- * Customize the logic for your institution. 
-- * This example uses the location_cd.
-- * Skip this section if you do not have ICU data.
--------------------------------------------------------------
--                 <dimcode>\i2b2\Visit Details\ServiceDepartments\Inpatient Visits\Intensive Care\</dimcode>
--                 <tooltip>Visit Details \ Clinical Service Department per O2 \ Inpatient Visits</tooltip>

drop table icu_dates;
create table icu_dates (
	patient_num,
	start_date,
	end_date,
    primary key (patient_num, start_date, end_date)
)
as
select distinct obs.patient_num, trunc(obs.start_date), trunc(coalesce(obs.end_date, current_date))
from nightherondata.observation_fact obs
join covid_pos_patients p
			on obs.patient_num=p.patient_num 
where obs.concept_cd in (
    'KUH|VISITDETAIL|HSPDEPT:101088160' -- BH28 ICU
  , 'KUH|VISITDETAIL|HSPDEPT:101010008' -- BH61 ICU
  , 'KUH|VISITDETAIL|HSPDEPT:101088340' -- BH63 ICU
  , 'KUH|VISITDETAIL|HSPDEPT:101088150' -- BH65 ICU 
)
and obs.end_date is null or obs.end_date>=p.covid_pos_date
and obs.start_date >= date '2019-10-01'
;
-- select * from icu_dates;


--------------------------------------------------------------
-- Create a list of lab tests and local codes
-- * Do not change the Test or LOINC columns.
-- * Change the C_BASECODE as needed.
-- * Repeat a lab if you use multiple codes (see PT as an example).
-- * Set your C_BASECODE=NULL if you do not have the lab (see procalcitonin as an example).
--------------------------------------------------------------
create table loinc_mapping as
select Test, LOINC, C_BASECODE
	from (
		select 'white blood cell count (Leukocytes)' Test, '6690-2' LOINC, 'KUH|COMPONENT_ID:3009' C_BASECODE
        from dual
		union all select 'neutrophil count','751-8', 'KUH|COMPONENT_ID:3012'
        from dual
		union all select 'lymphocyte count','731-0','KUH|COMPONENT_ID:3014'
        from dual
		union all select 'albumin','1751-7', 'KUH|COMPONENT_ID:1'
        from dual
		union all select 'albumin','1751-7', 'KUH|COMPONENT_ID:2023'
        from dual
		union all select 'albumin','1751-7', 'KUH|COMPONENT_ID:51066'
        from dual
		union all select 'lactate dehydrogenase (LDH)','2532-0', 'KUH|COMPONENT_ID:2070'
        from dual
		union all select 'alanine aminotransferase (ALT)','1742-6', 'KUH|COMPONENT_ID:2065'
        from dual
		union all select 'alanine aminotransferase (ALT)','1742-6', 'KUH|COMPONENT_ID:51082'
        from dual
		union all select 'aspartate aminotransferase (AST)','1920-8','KUH|COMPONENT_ID:2064'
        from dual
		union all select 'aspartate aminotransferase (AST)','1920-8','KUH|COMPONENT_ID:51154'
        from dual
		union all select 'total bilirubin','1975-2', 'KUH|COMPONENT_ID:2024'
        from dual
		union all select 'total bilirubin','1975-2', 'KUH|COMPONENT_ID:52182'
        from dual
		union all select 'creatinine','2160-0', 'KUH|COMPONENT_ID:2009'
        from dual
		union all select 'creatinine','2160-0', 'KUH|COMPONENT_ID:51418'
        from dual
		union all select 'cardiac troponin','49563-0', 'KUH|COMPONENT_ID:2326'  -- TROPONIN I	TNI
        from dual
		union all select 'cardiac troponin','49563-0', 'KUH|COMPONENT_ID:2327'  -- TROPONIN I, POC	TNIP
        from dual
		union all select 'D-dimer','7799-0', 'KUH|COMPONENT_ID:3094'
        from dual
		union all select 'prothrombin time (PT)','5902-2', 'KUH|COMPONENT_ID:52032'
        from dual
		union all select 'procalcitonin','33959-8', 'KUH|COMPONENT_ID:664'
        from dual
		union all select 'C-reactive protein (CRP)','1988-5', 'KUH|COMPONENT_ID:3186'
        from dual
	) l
;
/* eyeball it:
select * from loinc_mapping lm
left join dconnolly.counts_by_concept cbc on cbc.concept_cd = lm.c_basecode
order by lm.test, patients desc;

find more candidates:
select cbc.*, cc.* from clarity.clarity_component cc
left join dconnolly.counts_by_concept cbc on cbc.concept_cd = 'KUH|COMPONENT_ID:' || component_id
where lower(name) like '%prothrombin%';
*/


--************************************************************
--************************************************************
--*** Create the data tables
--************************************************************
--************************************************************

--------------------------------------------------------------
-- Create DailyCounts table
-- * Customize the new_deaths logic as needed.
-- * Set patients_in_icu = -2 if you do not have ICU data
-- * Set new_deaths = -2 if you do not have death data
--------------------------------------------------------------
create table daily as
select d.d, 
		(select count(*) 
			from covid_pos_patients p 
			where p.covid_pos_date=d.d
		) new_positive_cases,
		(select count(distinct patient_num) 
			from icu_dates i 
			where i.start_date<=d.d and i.end_date>=d.d
		) patients_in_icu,
		(select count(*) 
			from patient_dimension t 
			where t.death_date=d.d and t.patient_num in (select patient_num from covid_pos_patients)
		) new_deaths
	from date_list d
;

--------------------------------------------------------------
-- Create Demographics table
-- * Customize the sex_cd codes as needed.
--------------------------------------------------------------
;with a as (
	select (case sex_cd when 'M' then 'Male' when 'F' then 'Female' else 'Other' end) sex, age_in_years_num age
	from patient_dimension
	where patient_num in (select patient_num from #covid_pos_patients)
)
select sex, count(*) total_patients,
		sum(case when age between 0 and 2 then 1 else 0 end) age_0to2,
		sum(case when age between 3 and 5 then 1 else 0 end) age_3to5,
		sum(case when age between 6 and 11 then 1 else 0 end) age_6to11,
		sum(case when age between 12 and 17 then 1 else 0 end) age_12to17,
		sum(case when age between 18 and 25 then 1 else 0 end) age_18to25,
		sum(case when age between 26 and 49 then 1 else 0 end) age_26to49,
		sum(case when age between 50 and 69 then 1 else 0 end) age_50to69,
		sum(case when age between 70 and 79 then 1 else 0 end) age_70to79,
		sum(case when age >= 80 then 1 else 0 end) age_80plus
	into #demographics
	from (
		select sex, age from a
		union all
		select 'All', age from a
	) t
	group by sex

--------------------------------------------------------------
-- Create Labs table
--------------------------------------------------------------
select loinc, days_since_positive, 
		count(*) num_patients, avg(val) mean_value, stdev(val) stdev_val
	into #labs
	from (
		select loinc, patient_num, days_since_positive, avg(nval_num) val
		from (
			select f.*, l.loinc, datediff(dd,p.covid_pos_date,f.start_date)+1 days_since_positive
			from observation_fact f
				inner join #covid_pos_patients p 
					on f.patient_num=p.patient_num
				inner join #loinc_mapping l
					on f.concept_cd=l.c_basecode
			where f.nval_num is not null and l.c_basecode is not null
		) t
		where days_since_positive>=-6
		group by loinc, patient_num, days_since_positive
	) t
	group by loinc, days_since_positive

--------------------------------------------------------------
-- Create Diagnosis table
-- * Customize to select ICD9 and ICD10 codes.
--------------------------------------------------------------
select replace(replace(concept_cd,'DIAG|ICD10:',''),'DIAG|ICD9:','') icd_code,
		(case when concept_cd like 'DIAG|ICD10:%' then 10 else 9 end) icd_version,
		num_patients
	into #diagnoses
	from (
		select concept_cd, count(distinct patient_num) num_patients
		from (
			select f.*, datediff(dd,p.covid_pos_date,f.start_date)+1 days_since_positive
			from observation_fact f
				inner join #covid_pos_patients p 
					on f.patient_num=p.patient_num
			where concept_cd like 'DIAG|ICD%'
		) t
		where days_since_positive>=-6
		group by concept_cd
	) t


--************************************************************
--************************************************************
--*** Finish up
--************************************************************
--************************************************************

--------------------------------------------------------------
-- Obfuscate as needed
-- * Change the small count threshold, add random numbers, etc.
-- * Or, you can skip the queries if obfuscation is not needed.
--------------------------------------------------------------
update #daily
	set new_positive_cases = (case when new_positive_cases between 1 and 9 then -1 else new_positive_cases end),
		patients_in_icu = (case when patients_in_icu between 1 and 9 then -1 else patients_in_icu end),
		new_deaths = (case when new_deaths between 1 and 9 then -1 else new_deaths end)
update #demographics
	set total_patients = (case when total_patients between 1 and 9 then -1 else total_patients end),
		age_0to2 = (case when age_0to2 between 1 and 9 then -1 else age_0to2 end),
		age_3to5 = (case when age_3to5 between 1 and 9 then -1 else age_3to5 end),
		age_6to11 = (case when age_6to11 between 1 and 9 then -1 else age_6to11 end),
		age_12to17 = (case when age_12to17 between 1 and 9 then -1 else age_12to17 end),
		age_18to25 = (case when age_18to25 between 1 and 9 then -1 else age_18to25 end),
		age_26to49 = (case when age_26to49 between 1 and 9 then -1 else age_26to49 end),
		age_50to69 = (case when age_50to69 between 1 and 9 then -1 else age_50to69 end),
		age_70to79 = (case when age_70to79 between 1 and 9 then -1 else age_70to79 end),
		age_80plus = (case when age_80plus between 1 and 9 then -1 else age_80plus end)
update #labs
	set num_patients = (case when num_patients<10 then -1 else num_patients end),
		stdev_val = (case when num_patients<10 then -1 else stdev_val end)
update #diagnoses
	set num_patients = (case when num_patients<10 then -1 else num_patients end)

--------------------------------------------------------------
-- View the final tables
-- * Change the siteid to a unique value for your institution
-- * Save to CSV files (no headers) named:
-- * DailyCounts-SiteID.csv
-- * Demographics-SiteID.csv
-- * Labs-SiteID.csv
-- * Diagnoses-SiteID.csv
--------------------------------------------------------------
select 'BIDMC' siteid, * from #daily order by date
select 'BIDMC' siteid, * from #demographics
select 'BIDMC' siteid, * from #labs order by loinc, days_since_positive
select 'BIDMC' siteid, * from #diagnoses order by num_patients desc

