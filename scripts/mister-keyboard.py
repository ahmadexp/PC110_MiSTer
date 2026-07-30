#!/usr/bin/env python3
"""Inject Linux keycodes through a temporary full uinput keyboard.

MiSTer may ignore narrowly described uinput devices during core reload.  This
helper advertises the standard keyboard key range plus repeat support, waits for
Main to enumerate it, and can repeat one key across a BIOS startup window.
"""

import argparse
import fcntl
import os
import struct
import time


UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_SET_PHYS = 0x4004556C
UI_DEV_CREATE = 0x5501
UI_DEV_DESTROY = 0x5502
EV_SYN = 0
EV_KEY = 1
EV_REP = 20
SYN_REPORT = 0


def emit(fd, event_type, code, value):
    os.write(fd, struct.pack("llHHi", 0, 0, event_type, code, value))


def send_key(fd, code):
    emit(fd, EV_KEY, code, 1)
    emit(fd, EV_SYN, SYN_REPORT, 0)
    time.sleep(0.04)
    emit(fd, EV_KEY, code, 0)
    emit(fd, EV_SYN, SYN_REPORT, 0)


def send_chord(fd, codes):
    for code in codes:
        emit(fd, EV_KEY, code, 1)
    emit(fd, EV_SYN, SYN_REPORT, 0)
    time.sleep(0.12)
    for code in reversed(codes):
        emit(fd, EV_KEY, code, 0)
    emit(fd, EV_SYN, SYN_REPORT, 0)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "keycode", type=int, nargs="+", help="Linux input keycodes (F1 is 59)"
    )
    parser.add_argument("--delay", type=float, default=5.0,
                        help="enumeration delay before the first key")
    parser.add_argument("--duration", type=float, default=0.0,
                        help="repeat the key for this many seconds")
    parser.add_argument("--interval", type=float, default=0.25,
                        help="seconds between repeated keys")
    parser.add_argument("--chord", action="store_true",
                        help="press all supplied keycodes simultaneously")
    args = parser.parse_args()

    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_REP)
    for code in range(1, 256):
        fcntl.ioctl(fd, UI_SET_KEYBIT, code)
    # MiSTer merges input interfaces by their physical identifier and ignores
    # devices with neither Phys nor Uniq metadata during its input scan.
    fcntl.ioctl(fd, UI_SET_PHYS, b"pc110-remote/input0\0")

    # uinput_user_dev: name[80], input_id (4 x u16), ff_effects_max, abs arrays.
    identity = struct.pack(
        "80sHHHHI", b"PC110 Test Keyboard", 0x03, 0x046D, 0xC31C, 1, 0
    )
    os.write(fd, identity + bytes(4 * 64 * 4))
    fcntl.ioctl(fd, UI_DEV_CREATE)

    try:
        time.sleep(args.delay)
        deadline = time.monotonic() + args.duration
        if args.chord:
            send_chord(fd, args.keycode)
        elif len(args.keycode) > 1:
            for code in args.keycode:
                send_key(fd, code)
                time.sleep(args.interval)
        else:
            send_key(fd, args.keycode[0])
            while time.monotonic() < deadline:
                time.sleep(args.interval)
                send_key(fd, args.keycode[0])
        time.sleep(0.5)
    finally:
        fcntl.ioctl(fd, UI_DEV_DESTROY)
        os.close(fd)


if __name__ == "__main__":
    main()
