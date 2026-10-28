create or replace package test_inbound as
  --%suite(inbound: receiving, acknowledging and processing)

  --%test(An accepted message is stored as NEW and gets AA)
  procedure accepted;

  --%test(A message sent twice is stored once and gets the same ACK)
  procedure duplicate;

  --%test(Something that isn't HL7 gets AR and isn't stored)
  procedure not_hl7;

  --%test(A message with no control id gets AR)
  procedure no_control_id;

  --%test(A message type wardround doesn't use is IGNORED)
  procedure ignored_type;

  --%test(A bad message doesn't stop the ones after it)
  procedure error_then_next;

  --%test(A message in error can be reprocessed once the mapping is added)
  procedure reprocess_after_mapping;

  --%test(Only messages in error or held can be reprocessed)
  --%throws(-20004)
  procedure reprocess_done;

  --%test(purge_applied deletes old applied messages and keeps errors)
  procedure purge_keeps_errors;

  --%test(process applies at most p_max new messages)
  procedure process_max;

  --%test(A message with an unreadable MSH-7 is stored, with no time)
  procedure bad_time_still_stored;
end test_inbound;
/
