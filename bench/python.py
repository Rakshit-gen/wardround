"""Times the Python side without a database: generating the default feed,
reading a field from every message, and framing and unframing the whole
feed as MLLP in 64 KB reads. Each step runs RUNS times.

  python bench/python.py [RUNS]
"""

import platform
import sys
import time

from wardround import hl7, mllp
from wardround.cli import timing
from wardround.feed import Feed


def timed(runs, step):
    secs, result = [], None
    for _ in range(runs):
        began = time.perf_counter()
        result = step()
        secs.append(time.perf_counter() - began)
    return secs, result


def main(runs: int) -> None:
    print(f"Python {platform.python_version()} on {platform.machine()}, {runs} runs of each step")

    secs, feed = timed(runs, lambda: [o.raw for o in Feed().messages()])
    print(f"generate {len(feed)} messages: {timing(secs)}")

    secs, fins = timed(runs, lambda: [hl7.fields_of(m, "PV1")[19] for m in feed])
    assert all(fins), "a message without PV1-19"
    print(f"PV1-19 of {len(feed)} messages: {timing(secs)}")

    stream = b"".join(mllp.frame(m) for m in feed)

    def unframe():
        chunks = (stream[i : i + 65536] for i in range(0, len(stream), 65536))
        return list(mllp.frames(chunks))

    secs, back = timed(runs, unframe)
    assert back == feed, "unframing gave back different messages"
    print(f"unframe {len(stream) / 1e6:.1f} MB, {len(back)} messages: {timing(secs)}")


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 5)
