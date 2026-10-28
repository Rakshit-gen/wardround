-- Lab orders overdue.
--
-- Requirement: as of the end of the period, the lab orders placed in the
-- period that have no final result yet although their target time has
-- passed, by test and priority, with the oldest one so the lab can chase
-- it. Cancelled orders aren't overdue; orders with no agreed target
-- can't be.
--
-- Binds: :from_day and :to_day as YYYY-MM-DD; orders placed on or after
-- from_day and before to_day, looked at as of to_day.
with as_of as (
  select to_date(:from_day, 'YYYY-MM-DD') as from_dt, to_date(:to_day, 'YYYY-MM-DD') as to_dt
    from dual
),
overdue as (
  select o.placer_no,
         o.catalog_cd,
         o.priority,
         o.ordered_dt,
         1440 * (a.to_dt - o.ordered_dt) - t.minutes as minutes_over
    from orders o
    join tat_targets t on t.catalog_cd = o.catalog_cd and t.priority = o.priority
   cross join as_of a
   where o.ordered_dt >= a.from_dt
     and o.ordered_dt < a.to_dt
     and o.status <> 'CANCELLED'
     and (o.verified_dt is null or o.verified_dt >= a.to_dt)
     and o.ordered_dt + t.minutes / 1440 < a.to_dt
)
select cv.meaning as test,
       d.priority,
       count(*) as orders,
       round(max(d.minutes_over)) as most_min_over,
       min(d.placer_no) keep (dense_rank first order by d.ordered_dt) as oldest_order
  from overdue d
  join code_values cv on cv.code_value = d.catalog_cd
 group by cv.meaning, d.priority
 order by count(*) desc, cv.meaning, d.priority desc;
