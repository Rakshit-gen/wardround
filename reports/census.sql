-- Midnight census by unit.
--
-- Requirement: for each unit, how many patients were in it at midnight
-- on an average night of the period, the busiest night, and what share
-- of its staffed beds that is. A patient is in a unit at midnight if a
-- stretch of their location history covers midnight; patients waiting
-- in the ED for a ward bed count in the ED, where they are. Cancelled
-- visits don't count.
--
-- Binds: :from_day and :to_day as YYYY-MM-DD; the nights counted are
-- the midnights from from_day up to the day before to_day.
with nights as (
  select to_date(:from_day, 'YYYY-MM-DD') + level - 1 as midnight
    from dual
 connect by level <= to_date(:to_day, 'YYYY-MM-DD') - to_date(:from_day, 'YYYY-MM-DD')
),
census as (
  select n.midnight, l.unit_cd, count(*) as patients
    from nights n
    join encounter_locations l
      on l.beg_dt <= n.midnight and (l.end_dt is null or l.end_dt > n.midnight)
    join encounters e on e.encntr_id = l.encntr_id
   where e.status <> 'CANCELLED'
   group by n.midnight, l.unit_cd
)
select cv.meaning as unit,
       u.staffed_beds as beds,
       count(*) as nights,
       round(avg(nvl(c.patients, 0)), 1) as avg_census,
       max(nvl(c.patients, 0)) as peak_census,
       round(100 * avg(nvl(c.patients, 0)) / u.staffed_beds, 1) as occupancy_pct
  from units u
  join code_values cv on cv.code_value = u.unit_cd
 cross join nights n
  left join census c on c.unit_cd = u.unit_cd and c.midnight = n.midnight
 group by cv.meaning, u.staffed_beds, u.kind
 order by decode(u.kind, 'ED', 1, 'WARD', 2, 3), cv.meaning;
