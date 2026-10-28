import threading

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
