"""MLLP, the framing HL7 v2 uses over TCP: 0x0b, the message, 0x1c 0x0d."""

import socket
import socketserver
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
    """Sends messages one at a time and waits for each ACK, as feeds do."""

    def __init__(self, host: str, port: int, timeout: float = 30.0):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self._acks = frames(_reads(self.sock))

    def send(self, message: str) -> str:
        self.sock.sendall(frame(message))
        try:
            return next(self._acks)
        except StopIteration:
            raise ConnectionError("the listener closed the connection") from None

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
                self.request.sendall(frame(receive(message)))

    socketserver.TCPServer.allow_reuse_address = True
    return socketserver.TCPServer((host, port), Handler)
