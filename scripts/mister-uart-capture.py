#!/usr/bin/env python3
"""Capture a MiSTer UART without blocking on modem-control state."""

import argparse
import os
import select
import termios
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output")
    parser.add_argument("--device", default="/dev/ttyS1")
    parser.add_argument("--seconds", type=float, default=30.0)
    args = parser.parse_args()

    fd = os.open(args.device, os.O_RDONLY | os.O_NONBLOCK | os.O_NOCTTY)
    attrs = termios.tcgetattr(fd)
    attrs[0] = 0
    attrs[1] = 0
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attrs[3] = 0
    attrs[4] = termios.B115200
    attrs[5] = termios.B115200
    termios.tcsetattr(fd, termios.TCSANOW, attrs)

    deadline = time.monotonic() + args.seconds
    with open(args.output, "wb") as output:
        while time.monotonic() < deadline:
            readable, _, _ = select.select([fd], [], [], 0.25)
            if readable:
                try:
                    output.write(os.read(fd, 4096))
                except BlockingIOError:
                    pass
    os.close(fd)


if __name__ == "__main__":
    main()
