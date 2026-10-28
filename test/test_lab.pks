create or replace package test_lab as
  --%suite(lab: orders and results)

  --%beforeeach
  procedure visit;

  --%test(ORM NW places a routine order with its order time)
  procedure new_order;

  --%test(OBR-27 component 6 S makes an order stat)
  procedure stat_order;

  --%test(An order sent twice is placed once)
  procedure order_resent;

  --%test(An order for a visit not registered yet is held)
  procedure order_before_visit;

  --%test(Final results complete the order at the time they were reported)
  procedure final_results;

  --%test(A final result closes the preliminary one it replaces)
  procedure preliminary_then_final;

  --%test(A correction is a new version and doesn't move the verified time)
  procedure correction;

  --%test(A preliminary result that arrives after the final one is ignored)
  procedure late_preliminary;

  --%test(A final result reprocessed after its correction doesn't replace it)
  procedure final_after_correction;

  --%test(current_results shows only the latest version of each result)
  procedure current_results_view;

  --%test(Results for an order that hasn't arrived are held until it does)
  procedure results_before_order;

  --%test(ORM CA cancels an order, and results for it are an error)
  procedure cancelled_order;

  --%test(An order with results can't be cancelled)
  procedure cancel_after_results;

  --%test(Values that aren't plain numbers are kept as text, unknown flags as A)
  procedure text_values;

  --%test(A result code with no alias is an error and nothing is applied)
  procedure unmapped_result;
end test_lab;
/
