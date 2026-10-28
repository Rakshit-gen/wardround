-- The current version of each result, which is what a clinician would
-- see: older versions stay in clinical_events for the audit trail.
create or replace view current_results as
select ce.event_id,
       ce.encntr_id,
       e.fin,
       ce.order_id,
       o.placer_no,
       cv.meaning as result,
       ce.result_val,
       ce.result_num,
       ce.units,
       ce.normal_range,
       ce.abnormal,
       ce.status,
       ce.observed_dt,
       ce.verified_dt,
       ce.valid_from as reported_dt
  from clinical_events ce
  join encounters e on e.encntr_id = ce.encntr_id
  join code_values cv on cv.code_value = ce.event_cd
  left join orders o on o.order_id = ce.order_id
 where ce.valid_until is null;
