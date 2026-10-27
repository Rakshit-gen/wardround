create or replace package lab as
  -- Applies lab orders and results.
  --
  -- ORM^O01, one order per message: ORC-1 is NW for a new order and CA
  -- to cancel one; the placer order number is ORC-2 (or OBR-2), the test
  -- OBR-4, the priority component 6 of OBR-27 (S is stat), the order
  -- time ORC-9 (or MSH-7) and the visit PV1-19.
  --
  -- ORU^R01: each OBR and the OBX segments after it. OBR-2 names the
  -- order, OBR-7 is when the specimen was collected, OBR-22 when the
  -- results were reported. Each OBX is one result: code OBX-3, value
  -- OBX-5, units OBX-6, normal range OBX-7, flag OBX-8, status OBX-11
  -- (P preliminary, F final, C corrected), observed at OBX-14.
  --
  -- A result for an order that hasn't arrived raises waiting_for, so it's
  -- held until the order comes. A new version of a result closes the
  -- previous one at the time it was reported; a preliminary result that
  -- turns up after the final one is ignored. The order's verified time
  -- is when its first final result was reported, which is what
  -- turnaround is measured to. Doesn't commit.

  procedure apply_order(p_msg hl7.t_message);

  procedure apply_results(p_msg hl7.t_message, p_msg_id number default null);
end lab;
/
