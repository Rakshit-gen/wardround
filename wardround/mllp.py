"""MLLP, the framing HL7 v2 uses over TCP: 0x0b, the message, 0x1c 0x0d."""

import socket
import socketserver
import sys
import time
from collections.abc import Callable, Iterator

START = b"\x0b"
END = b"\x1c\r"
ENCODING = "utf-8"


def frame(message: str) -> bytes:
    return START + message.encode(ENCODING) + END


def frames(chunks: Iterator[bytes]) -> Iterator[str]:
    """The messages in a stream of bytes read off a socket, however the
    reads split them. Bytes outside a frame are dropped."""
    buf = b""
    for chunk in chunks:
        buf += chunk
        while True:
            end = buf.find(END)
            if end < 0:
                break
            start = buf.rfind(START, 0, end)
            if start >= 0:
                yield buf[start + 1 : end].decode(ENCODING)
            buf = buf[end + len(END) :]


def _reads(sock: socket.socket) -> Iterator[bytes]:
    while chunk := sock.recv(65536):
        yield chunk


class Sender:
    """Sends messages one at a time and waits for each ACK, as feeds do.

    If the connection drops before the ACK comes, it connects again and
    sends the same message, up to retries times. Sending a message twice
    is safe: the listener stores a resend once and gives the same ACK."""

    def __init__(
        self, host: str, port: int, timeout: float = 30.0, retries: int = 0, wait: float = 1.0
    ):
        self.address = (host, port)
        self.timeout = timeout
        self.retries = retries
        self.wait = wait
        self.reconnects = 0
        self._connect()

    def _connect(self) -> None:
        self.sock = socket.create_connection(self.address, timeout=self.timeout)
        self._acks = frames(_reads(self.sock))

    def _send_once(self, message: str) -> str:
        self.sock.sendall(frame(message))
        try:
            return next(self._acks)
        except StopIteration:
            raise ConnectionError("the listener closed the connection") from None

    def send(self, message: str) -> str:
        for attempt in range(self.retries + 1):
            try:
                return self._send_once(message)
            except OSError:
                if attempt == self.retries:
                    raise
                self.sock.close()
                time.sleep(self.wait)
                self._connect()
                self.reconnects += 1
        raise AssertionError("unreachable")

    def close(self) -> None:
        self.sock.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


def server(host: str, port: int, receive: Callable[[str], str]) -> socketserver.TCPServer:
    """A listener that passes each message to receive and sends back the
    ACK it returns. receive must have stored the message for good (the
    database committed) before it returns, so a message that was ACKed is
    never lost. One connection at a time, which is how a feed sends."""

    class Handler(socketserver.BaseRequestHandler):
        def handle(self):
            for message in frames(_reads(self.request)):
                try:
                    ack = receive(message)
                except Exception as e:
                    # Not stored, so no ACK: closing the connection makes
                    # the feed send it again, which is safe since a
                    # message stored twice is stored once.
                    print(f"closing the connection, message not stored: {e}", file=sys.stderr)
                    return
                self.request.sendall(frame(ack))

    socketserver.TCPServer.allow_reuse_address = True
    return socketserver.TCPServer((host, port), Handler)
