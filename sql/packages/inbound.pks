create or replace package inbound as
  -- Takes HL7 messages in and applies them.

  -- Stores a message and returns the ACK to send back. The caller
  -- commits before sending it, so an accepted message is never lost.
  -- A message seen before (same sender and control id) isn't stored
  -- again and gets the same ACK as the first copy. One that can't be
  -- read gets AR and isn't stored.
  function receive(p_raw clob) return varchar2;

  -- Applies up to p_max new messages in the order received, then retries
  -- held ones for as long as that gets any further. Each message is
  -- applied or not as a whole. Returns how many were applied. Doesn't
  -- commit.
  function process(p_max pls_integer default 10000) return pls_integer;

  -- Puts a message in error back in the queue, after the mapping or the
  -- data it needed has been fixed.
  procedure reprocess(p_msg_id number);

  -- Deletes messages applied or ignored before p_before, which the
  -- visits, orders and results no longer need. Messages held or in error
  -- are kept however old, since someone still has to look at them.
  -- Returns how many were deleted. Doesn't commit.
  function purge(p_before date) return pls_integer;
end inbound;
/
