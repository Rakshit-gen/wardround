-- Length of stay of inpatients.
--
-- Requirement: for inpatient stays that ended in the period, by the unit
-- the patient left from and for all units, how many there were and
-- their mean, median and 90th percentile length in days. A stay runs
-- from the admission to inpatient (not ED arrival) to discharge.
--
-- Binds: :from_day and :to_day as YYYY-MM-DD, discharges on or after
-- from_day and before to_day.
with stays as (
  select e.encntr_id,
         e.disch_dt - e.inpatient_dt as days,
         (select l.unit_cd
            from encounter_locations l
           where l.encntr_id = e.encntr_id
           order by l.beg_dt desc
           fetch first 1 row only) as unit_cd
    from encounters e
   where e.status = 'DISCHARGED'
     and e.inpatient_dt is not null
     and e.disch_dt >= to_date(:from_day, 'YYYY-MM-DD')
     and e.disch_dt < to_date(:to_day, 'YYYY-MM-DD')
)
select case when grouping(cv.meaning) = 1 then 'ALL' else cv.meaning end as unit,
       count(*) as discharges,
       round(avg(s.days), 2) as mean_days,
       round(median(s.days), 2) as median_days,
       round(percentile_cont(0.9) within group (order by s.days), 2) as p90_days
  from stays s
  join code_values cv on cv.code_value = s.unit_cd
 group by rollup(cv.meaning)
 order by grouping(cv.meaning), cv.meaning;
