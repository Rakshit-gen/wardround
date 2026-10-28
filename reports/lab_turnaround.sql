-- Lab turnaround.
--
-- Requirement: for lab orders whose first final result was reported in
-- the period, by test and priority, how many there were, the median and
-- 90th percentile minutes from order to result, the target the lab has
-- agreed for that test and priority, and the share that met it. Orders
-- with no agreed target (routine troponin and lactate) are shown with no
-- target and no share.
--
-- Binds: :from_day and :to_day as YYYY-MM-DD, results reported on or
-- after from_day and before to_day.
with done as (
  select o.catalog_cd,
         o.priority,
         1440 * (o.verified_dt - o.ordered_dt) as minutes
    from orders o
   where o.status = 'COMPLETED'
     and o.verified_dt >= to_date(:from_day, 'YYYY-MM-DD')
     and o.verified_dt < to_date(:to_day, 'YYYY-MM-DD')
)
select cv.meaning as test,
       d.priority,
       count(*) as orders,
       round(median(d.minutes)) as median_min,
       round(percentile_cont(0.9) within group (order by d.minutes)) as p90_min,
       t.minutes as target_min,
       case when t.minutes is not null
            then round(100 * count(case when d.minutes <= t.minutes then 1 end) / count(*), 1)
       end as within_target_pct
  from done d
  join code_values cv on cv.code_value = d.catalog_cd
  left join tat_targets t on t.catalog_cd = d.catalog_cd and t.priority = d.priority
 group by cv.meaning, d.priority, t.minutes
 order by cv.meaning, d.priority desc;
