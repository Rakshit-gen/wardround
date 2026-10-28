-- 30-day readmissions.
--
-- Requirement: of the inpatient stays that ended in the period, the
-- share where the same patient was admitted as an inpatient again within
-- 30 days of discharge, by where they were discharged to and overall.
-- Patients who died or went to another acute hospital can't be
-- readmitted here in a way that says anything about their care, so
-- those stays aren't counted. A stay with no disposition recorded is
-- counted, as "NOT_RECORDED".
--
-- Binds: :from_day and :to_day as YYYY-MM-DD, discharges on or after
-- from_day and before to_day. The 30 days may run past to_day.
with index_stays as (
  select e.encntr_id, e.person_id, e.disch_dt, e.disch_disp_cd
    from encounters e
   where e.status = 'DISCHARGED'
     and e.inpatient_dt is not null
     and e.disch_dt >= to_date(:from_day, 'YYYY-MM-DD')
     and e.disch_dt < to_date(:to_day, 'YYYY-MM-DD')
     and (e.disch_disp_cd is null
          or e.disch_disp_cd not in (select code_value from code_values
                                      where code_set = 19 and meaning in ('EXPIRED', 'TRANSFER_ACUTE')))
),
flagged as (
  select i.*,
         case when exists (select null
                             from encounters r
                            where r.person_id = i.person_id
                              and r.encntr_id <> i.encntr_id
                              and r.status <> 'CANCELLED'
                              and r.inpatient_dt > i.disch_dt
                              and r.inpatient_dt <= i.disch_dt + 30)
              then 1 else 0 end as readmitted
    from index_stays i
)
select case when grouping(nvl(cv.meaning, 'NOT_RECORDED')) = 1 then 'ALL'
            else nvl(cv.meaning, 'NOT_RECORDED') end as disposition,
       count(*) as stays,
       sum(f.readmitted) as readmitted,
       round(100 * sum(f.readmitted) / count(*), 1) as rate_pct
  from flagged f
  left join code_values cv on cv.code_value = f.disch_disp_cd
 group by rollup(nvl(cv.meaning, 'NOT_RECORDED'))
 order by grouping(nvl(cv.meaning, 'NOT_RECORDED')), 1;
