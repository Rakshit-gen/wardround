import threading

import pytest

from wardround import mllp


def test_frame():
    assert mllp.frame("MSH|x") == b"\x0bMSH|x\x1c\r"


def test_frames_split_across_reads():
    data = mllp.frame("one") + mllp.frame("two") + mllp.frame("three")
    chunks = [data[i : i + 3] for i in range(0, len(data), 3)]
    assert list(mllp.frames(iter(chunks))) == ["one", "two", "three"]


def test_frames_drop_bytes_outside_a_frame_and_a_partial_one():
    data = b"noise" + mllp.frame("one") + b"\r\n" + b"\x0bcut off"
    assert list(mllp.frames(iter([data]))) == ["one"]


def test_text_that_is_not_ascii_survives():
    assert list(mllp.frames(iter([mllp.frame("DOE^ZOË")]))) == ["DOE^ZOË"]


def test_sender_and_server_round_trip():
    received = []

    def receive(message):
        received.append(message)
        return "MSA|AA|" + message

    srv = mllp.server("127.0.0.1", 0, receive)
    port = srv.server_address[1]
    thread = threading.Thread(target=srv.serve_forever, daemon=True)
    thread.start()
    try:
        with mllp.Sender("127.0.0.1", port) as sender:
            assert sender.send("m1") == "MSA|AA|m1"
            assert sender.send("m2") == "MSA|AA|m2"
    finally:
        srv.shutdown()
        srv.server_close()
    assert received == ["m1", "m2"]


def test_listener_sends_no_ack_for_a_message_it_could_not_store():
    def receive(message):
        if message == "bad":
            raise RuntimeError("database down")
        return "ACK " + message

    srv = mllp.server("127.0.0.1", 0, receive)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    try:
        with mllp.Sender("127.0.0.1", srv.server_address[1]) as sender:
            assert sender.send("ok") == "ACK ok"
            with pytest.raises(ConnectionError):
                sender.send("bad")
    finally:
        srv.shutdown()
        srv.server_close()


def test_sender_reconnects_and_sends_again():
    calls = []

    def receive(message):
        calls.append(message)
        if len(calls) == 1:
            raise RuntimeError("database restarting")
        return "ACK " + message

    srv = mllp.server("127.0.0.1", 0, receive)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    try:
        with mllp.Sender("127.0.0.1", srv.server_address[1], retries=2, wait=0) as sender:
            assert sender.send("m1") == "ACK m1"
            assert sender.reconnects == 1
    finally:
        srv.shutdown()
        srv.server_close()
    assert calls == ["m1", "m1"]
