# ARS USB2PCMCIA-R support

This directory contains clean-room bring-up code for the ARS Technologies
USB2PCMCIA-R (`071f:0048`). The goal is to connect a physical 16-bit PC Card to
the PC110 core's existing ExCA/82365-compatible socket model.

## Confirmed hardware behavior

The adapter initially exposes the exact factory endpoint layout documented for
the Cypress EZ-USB FX2/FX2LP. Its `0xa0` request accesses volatile FX2 memory:

- `0x0000-0x3fff`: 16 KiB FX2 code RAM
- `0xe000-0xe1ff`: scratch RAM
- `0xe600-0xe6ff`: FX2 registers (`CPUCS` is at `0xe600`)
- EP1, EP2, EP4, EP6, and EP8 use the factory Cypress alternate settings

The ARS host enumerator normally downloads runtime firmware after attachment.
Without that step, the factory bulk endpoints do not consume or return data.

The boot EEPROM is only a Cypress `C0` identity record:

```text
c0 1f 07 48 00 00 00 00 ff 00 00 00 ff ff ff ff ...
```

It supplies VID `071f`, PID `0048`, and DID `0000`; it does not contain ARS
runtime firmware.

## Confirmed socket inputs

The safe probe produced these port-A samples with every output-enable clear:

```text
10 MB PC Card installed: IOA=f6
Socket empty:            IOA=ff
One contact only:         IOA=f7 (PA3 low, PA0 high)
```

Only PA0 and PA3 change, so they are the socket's two active-low card-detect
contacts. No other FX2 input changed between those two states. Both bits must
be low before attempting CIS access; `f7` means the card is mis-seated or one
card-detect contact is not making electrical contact.

## ARM probe/loader

`usb2pcmcia_probe.c` builds as an ARMv7/libusb utility for MiSTer. Its firmware
loader accepts only Intel HEX records targeting volatile code RAM and verifies
the complete image before starting the FX2 CPU. It has no EEPROM-write command.

Build with the standard MiSTer toolchain image:

```sh
docker run --rm -v "$PWD:/work" -w /work/sw/usb2pcmcia \
  misterkun/toolchain:latest make clean all
```

Useful commands:

```text
usb2pcmcia-probe info
usb2pcmcia-probe ram-read ADDRESS LENGTH [OUTPUT]
usb2pcmcia-probe ram-load FIRMWARE.ihx
usb2pcmcia-probe gpio-snapshot
```

On 2026-07-30 the CF-JVR101 produced `IOA=f7` with external 5 V applied. The
licensed runtime accepted control transfers, but both its D0000h attribute
window and the eight-register I/O window returned zero. This is a physical
socket/card-detect failure, not a guest bridge failure; keep `present=0` until
the safe probe reports both PA0 and PA3 low and a runtime CIS read is nonzero.

The old `fx2-read` spelling remains as a compatibility alias for `ram-read`.

## Safe probe firmware

`firmware/` is a volatile FX2 firmware used to inspect the board before its
card-side wiring is known. It keeps ports A-E as inputs, configures no bulk
endpoint, performs no GPIF transaction, and exposes two read-only requests:

- vendor IN `0xb0`, 20 bytes: format version and FX2 configuration, GPIO,
  output-enable, endpoint-status, pin-flag, and GPIF-idle registers.
- vendor IN `0xb1`, `wValue` = address, up to 64 bytes: read the boot EEPROM
  detected by the FX2 (`0x50` for one-byte or `0x51` for two-byte addressing).

The firmware uses [fx2lib](https://github.com/djmuhlestein/fx2lib) and SDCC. To
build without adding generated or third-party files to this repository:

```sh
git clone https://github.com/djmuhlestein/fx2lib /path/to/fx2lib
docker run --rm -v "$PWD:/work" -v /path/to/fx2lib:/fx2lib \
  -w /work/sw/usb2pcmcia/firmware debian:bookworm-slim \
  sh -lc 'apt-get update -qq && apt-get install -y -qq make sdcc && \
          make FX2LIBDIR=/fx2lib'
```

Loading this image changes only RAM. Disconnecting USB restores the adapter's
factory boot state.

## Integration boundary

The FPGA still presents the original Ricoh/82365 ExCA register interface to DOS.
A MiSTer ARM service will translate configured common-memory, attribute-memory,
and I/O windows into USB2PCMCIA-R transactions and feed card-detect/status/IRQ
events back through the existing management bridge. USB round-trip latency means
the bridge must use wait states and block caching; it cannot be wired directly to
an ISA-cycle combinational path.

## Vendor-supported runtime

The functional bridge uses only the public API supplied in the licensed
`install2rel` package. Vendor firmware, `arsenum4`, `isarw`, and
`libarsusb4.so` are not part of this repository and must not be redistributed
separately from the ARS hardware.

Install your own package on the MiSTer with:

```sh
./deploy-vendor.sh /path/to/install2rel root@192.168.10.251
```

On MiSTer, start the enumerator before loading the PC110 core:

```sh
/media/fat/linux/pc110-pcmcia/start-vendor.sh \
  >/tmp/pc110-pcmcia-enumerator.log 2>&1 &
```

`start-vendor.sh` provides the enumerator's required `/home/p` through a
temporary writable bind mount; it does not remount or modify MiSTer's
read-only root filesystem. Put the resource bases printed by the enumerator in
`/media/fat/linux/pc110-pcmcia/pc110-pcmcia.cfg`. The patched Main service
reloads that file at runtime.

PC Card software normally reads the CIS through attribute memory before it
enables I/O. If the ARS enumerator reports I/O resources but no physical-memory
resource, Main can provide a packed CIS tuple stream from
`/media/fat/linux/pc110-pcmcia/cis.hex`; it presents each packed byte at the
standard even attribute-memory addresses and shadows configuration-register
writes after the tuple stream. `sundisk-sdp3b.cis.hex` is the tuple chain from
the documented SunDisk SDP3B family dump in the companion Open-Source-PC110
hardware archive. Copy it to `cis.hex` only for a matching card.
Main reads `cis.hex` when the core initializes, so reload the core after adding
or changing that file.

## Panasonic CF-JVR101 profile

The CF-JVR101 is a 16-bit PC Card with a 16550-compatible, eight-register
serial interface. Panasonic's original DOS documentation supports COM1-COM4
and defaults to COM2 (`02F8h`, IRQ 3). The card's Windows 95 INF supplies the
remaining hardware configuration details:

- the card requires 5 V; use power-header position 2-3 only for bus power, or
  remove the jumper when using the adapter's external 5 V input
- configuration-register base: attribute offset `0200h`
- configuration-table index: `20h`; Card Services sets the COR level-IRQ bit,
  producing Panasonic's requested `60h` configuration byte
- configuration status: `08h`, enabling the PC Card audio path
- host I/O resource: one 8-byte, 16-bit-decode window

`cf-jvr101.cis.hex` encodes that profile as a synthetic CIS, including the
`PANASONIC` / `CF-JVR101` identity, 5 V requirement, eight-register I/O
window, level-triggered IRQ capability, audio flag, and configuration-register
mask. Copy it to `cis.hex` only for a CF-JVR101. It supplies guest-side Card
Services metadata; it cannot replace the real host I/O allocation that the ARS
Enumerator must create first.

Always disconnect USB power before inserting/removing the card or moving the
power header. The USB2PCMCIA-R factory setting is 1-2 (3.3 V), at which the
adapter can detect this card's mechanical presence but cannot read its CIS or
allocate a resource. When using external 5 V, remove the jumper, insert the
card, connect and turn on external power, and connect USB last. This ordering
is required by the adapter's vendor guide.

For the supported ARM text enumerator build, `make diagnostic-tools` also
builds `arsenum4-cis-inject`. If that executable is installed beside
`arsenum4`, `start-vendor.sh` uses it as a guarded fallback: it substitutes the
known CF-JVR101 tuple stream only when the vendor parser receives a uniform
open-bus scan, and leaves real CIS data untouched.

The vendor Enumerator must first print a real I/O allocation for the card.
Copy that host-side base to `io0` in `pc110-pcmcia.cfg` and only then set
`present=1`; the PC110 guest may map the window to a different address such as
COM2 because the bridge translates card-relative offsets. Never invent an ARS
resource base: the basic vendor API terminates callers that access an
unallocated resource.

The IBM PC110 DOS image already contains the original Socket Services and Card
Services stack in `C:\EZPLAY`. Panasonic's `DOSVIRC.SYS` must load after that
stack and uses `DOSVIRC.INI` to request its COM/IRQ assignment. The Panasonic
driver and radio application are licensed artifacts and are intentionally not
redistributed in this repository.

The Main patch dynamically opens the user-installed library, verifies all
documented API symbols, and forwards 8/16/32-bit I/O, burst common-memory,
burst attribute-memory, and IRQ10 operations. Dword I/O is split into the two
word cycles supported by the 16-bit PC Card bus. If the enumerator, library,
config, adapter, or card is missing, enabled guest windows return open bus
instead of blocking the CPU.

For read-only resource diagnosis, `make vendor-tools` builds `ars-readonly`.
It accepts a physical address in the documented `0xA0000-0xFFFFF` range and a
length of up to 4096 bytes. It resolves only `ArsInit`, `ArsExit`, and `rd8` and
therefore cannot issue a card write. Use only a memory base actually printed by
the enumerator: the vendor library terminates a caller that reads an unmapped
physical address.
