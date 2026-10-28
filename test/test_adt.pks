create or replace package test_adt as
  --%suite(adt: visits from registration messages)

  --%test(A04 registers an emergency visit in the ED)
  procedure register_emergency;

  --%test(A01 for an emergency visit makes it inpatient from the admission)
  procedure admit_from_ed;

  --%test(A direct A01 makes an inpatient visit from arrival)
  procedure direct_admit;

  --%test(The patient's MRN is the PID-3 repetition marked MR)
  procedure mrn_by_type;

  --%test(Transfers go in by event time, whatever order they arrive in)
  procedure transfers_out_of_order;

  --%test(A transfer sent twice changes nothing the second time)
  procedure transfer_resent;

  --%test(A transfer for a visit not registered yet is held, then applied)
  procedure held_until_registered;

  --%test(A03 discharges the visit and closes its last stretch)
  procedure discharge;

  --%test(A discharge before the last move is an error)
  procedure discharge_before_move;

  --%test(A13 undoes a discharge)
  procedure cancel_discharge;

  --%test(A11 after an ED admission makes the visit emergency again)
  procedure cancel_admit_from_ed;

  --%test(A11 after a direct admission cancels the visit)
  procedure cancel_direct_admit;

  --%test(A08 updates the patient's details)
  procedure update_patient;

  --%test(DG1 segments replace the visit's diagnoses, with DG1-15 marking the principal)
  procedure diagnosis_ranking;

  --%test(A unit with no alias is an error on the message, naming the code)
  procedure unmapped_unit;

  --%test(PV1-44 gives the arrival time when it's sent)
  procedure arrival_from_pv1_44;
end test_adt;
/
