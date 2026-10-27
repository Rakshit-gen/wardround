create or replace package adt as
  -- Applies ADT (admit, discharge, transfer) messages from registration:
  --   A04 register an emergency or outpatient visit
  --   A01 admit, and A06 change a visit to inpatient; for a visit already
  --       registered (an emergency patient being admitted) the visit
  --       becomes inpatient from the message's event time
  --   A02 transfer to another bed
  --   A03 discharge
  --   A08 update the patient's details
  --   A11 cancel an admission, A13 cancel a discharge
  --
  -- Times are the event time (EVN-6, else EVN-2, else MSH-7) unless the
  -- message carries its own: PV1-44 for arrival, PV1-45 for discharge.
  -- Messages are applied as of their event time, not their arrival, so a
  -- transfer that arrives after a later one still goes in the right
  -- place. Applying a message twice changes nothing the second time.
  --
  -- Raises waiting_for if the visit isn't registered yet, unmapped_code
  -- for a code with no alias, bad_field and out_of_step. Doesn't commit.

  procedure apply_message(p_msg hl7.t_message);

  -- Whether apply_message handles trigger event p_event (A01 and so on).
  function handles(p_event varchar2) return boolean;
end adt;
/
