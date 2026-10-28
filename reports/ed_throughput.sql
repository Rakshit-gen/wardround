-- ED throughput and boarding.
--
-- Requirement: for visits that arrived in the ED in the period, split by
-- whether they were admitted, how many there were, how long they spent
-- in the ED (median and 90th percentile, in hours) and how many are
-- still there. For admitted patients, boarding is the time from the
-- admission to leaving the ED for a bed; the report gives its median
-- and how many boarded for more than four hours.
--
-- Binds: :from_day and :to_day as YYYY-MM-DD, arrivals on or after
-- from_day and before to_day.
with ed_visits as (
  select e.encntr_id,
         e.arrive_dt,
         e.inpatient_dt,
         -- Leaving the ED is the end of the last ED stretch; null while
         -- the patient is still there.
         max(l.end_dt) keep (dense_rank last order by l.beg_dt) as left_ed
    from encounters e
    join encounter_locations l on l.encntr_id = e.encntr_id
    join units u on u.unit_cd = l.unit_cd and u.kind = 'ED'
   where e.status <> 'CANCELLED'
     and e.arrive_dt >= to_date(:from_day, 'YYYY-MM-DD')
     and e.arrive_dt < to_date(:to_day, 'YYYY-MM-DD')
   group by e.encntr_id, e.arrive_dt, e.inpatient_dt
),
timed as (
  select case when inpatient_dt is not null then 'ADMITTED' else 'NOT_ADMITTED' end as outcome,
         24 * (left_ed - arrive_dt) as ed_hours,
         case when inpatient_dt is not null then 24 * (left_ed - greatest(inpatient_dt, arrive_dt)) end as boarding_hours,
         case when left_ed is null then 1 else 0 end as still_in_ed
    from ed_visits
)
select case when grouping(outcome) = 1 then 'ALL' else outcome end as outcome,
       count(*) as visits,
       sum(still_in_ed) as still_in_ed,
       round(median(ed_hours), 1) as median_ed_hours,
       round(percentile_cont(0.9) within group (order by ed_hours), 1) as p90_ed_hours,
       round(median(boarding_hours), 1) as median_boarding_hours,
       count(case when boarding_hours > 4 then 1 end) as boarded_over_4h
  from timed
 group by rollup(outcome)
 order by grouping(outcome), outcome;
