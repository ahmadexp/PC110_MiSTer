#!/usr/bin/env python3
"""Read the live PC110 RTC diagnostic through the DE25 HPS GP bridge."""

import mmap
import os
import signal
import struct
import time


GP_BASE = 0x20020000
GP_OUT_OFFSET = 0x00
GP_IN_OFFSET = 0x10
RTC_SELECT = 1 << 21
DIAGNOSTIC_MASK = (
    (1 << 29)
    | (1 << 28)
    | (1 << 27)
    | (1 << 26)
    | (1 << 25)
    | (1 << 24)
    | (1 << 23)
    | RTC_SELECT
    | 0x7
)


def find_main_pid():
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as command_file:
                command = command_file.read().split(b"\0", 1)[0]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if command.endswith(b"/MiSTer"):
            return int(name)
    raise RuntimeError("MiSTer Main process not found")


def read_u32(mapping, offset):
    return struct.unpack_from("<I", mapping, offset)[0]


def write_u32(mapping, offset, value):
    struct.pack_into("<I", mapping, offset, value)


def read_pages(mapping, base):
    pages = []
    for page in range(8):
        write_u32(mapping, GP_OUT_OFFSET, base | RTC_SELECT | page)
        time.sleep(0.015)
        pages.append((read_u32(mapping, GP_IN_OFFSET) >> 21) & 0x3F)
    return pages


def decode(pages):
    second = pages[0] | (((pages[1] >> 2) & 0x3) << 6)
    minute_low = pages[1] & 0x3
    second_toggle = (pages[1] >> 5) & 1
    ce_toggle = (pages[1] >> 4) & 1
    state = (pages[2] >> 3) & 0x7
    freeze = (pages[2] >> 2) & 1
    divider = ((pages[2] & 0x3) << 1) | ((pages[6] >> 5) & 1)
    timeout = pages[3] | ((pages[4] & 0x1F) << 6)
    update = (pages[4] >> 5) & 1
    periodic_rate_low = pages[6] & 0x7
    return {
        "second": second,
        "minute_low": minute_low,
        "second_toggle": second_toggle,
        "ce_toggle": ce_toggle,
        "state": state,
        "freeze": freeze,
        "divider": divider,
        "timeout": timeout,
        "update": update,
        "periodic_rate_low": periodic_rate_low,
        "controls": pages[5],
        "flags": pages[7],
    }


main_pid = find_main_pid()
with open("/dev/mem", "r+b", buffering=0) as device:
    bridge = mmap.mmap(
        device.fileno(),
        0x1000,
        flags=mmap.MAP_SHARED,
        prot=mmap.PROT_READ | mmap.PROT_WRITE,
        offset=GP_BASE,
    )
    original = read_u32(bridge, GP_OUT_OFFSET)
    base = original & ~DIAGNOSTIC_MASK
    os.kill(main_pid, signal.SIGSTOP)
    try:
        time.sleep(0.05)
        first_pages = read_pages(bridge, base)
        time.sleep(1.1)
        second_pages = read_pages(bridge, base)
    finally:
        write_u32(bridge, GP_OUT_OFFSET, original)
        time.sleep(0.02)
        os.kill(main_pid, signal.SIGCONT)
        bridge.close()

first = decode(first_pages)
second = decode(second_pages)
print(f"Main PID: {main_pid}")
print(f"GPO restored: 0x{original:08X}")
print(f"first pages:  {[f'0x{page:02X}' for page in first_pages]}")
print(f"second pages: {[f'0x{page:02X}' for page in second_pages]}")
for label, sample in (("first", first), ("second", second)):
    print(
        f"{label}: second=0x{sample['second']:02X} "
        f"minute_low={sample['minute_low']} state={sample['state']} "
        f"timeout={sample['timeout']} freeze={sample['freeze']} "
        f"divider={sample['divider']} rate_low={sample['periodic_rate_low']} "
        f"ce_toggle={sample['ce_toggle']} "
        f"second_toggle={sample['second_toggle']} "
        f"update={sample['update']} controls=0x{sample['controls']:02X} "
        f"flags=0x{sample['flags']:02X}"
    )

if first["freeze"] or second["freeze"]:
    raise SystemExit("FAIL: RTC SET/freeze bit is asserted")
if first["divider"] != 2 or second["divider"] != 2:
    raise SystemExit("FAIL: RTC divider is not the expected 010b value")
if (
    first["second"] == second["second"]
    and first["second_toggle"] == second["second_toggle"]
):
    raise SystemExit("FAIL: RTC second did not advance")
print("PASS: PC110 RTC is running and its control registers are valid")
