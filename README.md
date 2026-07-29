# IBM Palm Top PC 110 for MiSTer

[![RTL tests](https://github.com/ahmadexp/PC110_MiSTer/actions/workflows/test.yml/badge.svg)](https://github.com/ahmadexp/PC110_MiSTer/actions/workflows/test.yml)
![Quartus](https://img.shields.io/badge/Quartus-17.0.2-blue)
![Target](https://img.shields.io/badge/target-DE10--Nano%20%2F%20MiSTer-orange)

This repository is a standalone MiSTer core for the IBM Palm Top PC 110. It
uses an open-source 486SX-compatible CPU and reusable PC components, while the
project identity, machine profile, chipset behavior, storage policy,
configuration and release artifact are PC110-specific. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the dependency boundary.

This is an engineering core, not yet a cycle-exact replacement for the whole
PC110 planar.  The current milestone gets the real 256 KiB IBM flash image in
front of a 486 CPU and implements enough of the board-specific decode to begin
real POST on hardware.  See [docs/STATUS.md](docs/STATUS.md) for the measured
and placeholder parts.

## What is implemented

- 486SX-compatible CPU, AT peripherals, IDE, floppy, VGA, keyboard, and mouse
- a fixed 30 MHz CPU profile, the closest currently characterized PC110 timing
- PC110 memory geometry: 4 MiB planar RAM plus the 16 MiB expansion card
- the 256 KiB PC110 flash mapped linearly at `C0000h-FFFFFh`
- VL82C420/SCAMP configuration interfaces at `22h/23h`, `24h/25h`,
  `74h/76h`, and `ECh/EDh`, including their observed unlock sequences
- per-16 KiB upper-memory shadow write protection
- Ricoh RB5C396/82365-compatible PCMCIA register file at `3E0h/3E1h`
- PC110 font-ROM bank controls at `1160h-1163h` and a 1 MiB font image in DDR
- inking interface, planar POS/config registers, and both captured EC windows
- PC110 CMOS equipment and 20 MiB memory fields

The implementation is derived from live hardware captures in
Open-Source-PC110, BIOS disassembly and trace work in Reverse-Engineering-PC110,
and behavioral observations from PC110-EMU.  PC110-EMU is used as an oracle,
not translated directly: its interpreter includes synthetic exits and
machine-specific shortcuts that are not hardware behavior.

## Hardware screenshots

### IBM Easy-Setup

The original IBM setup module running from the PC110 flash image, with working
keyboard navigation:

![IBM PC110 Easy-Setup](docs/images/ibm-pc110-easy-setup.png)

### IBM PC DOS J7.0/V and PersonaWare

PersonaWare V1.0 after an unattended boot, with Japanese fonts and keyboard
input working:

![IBM PC110 PersonaWare desktop](docs/images/ibm-pc110-personaware.png)

## Required ROMs

ROMs are not distributed by this repository.

Prepare the exact IBM 39H4551 PC110 flash:

```sh
scripts/prepare-roms.sh /path/to/pc110_bios.bin \
  /path/to/MSM538032E@SOP44.BIN
```

The supported BIOS is 262,144 bytes with SHA-256:

```text
232101c88466f311bcc32fbc215a4d7569f695ce19f9c07ca67ce2aee5232312
```

The script validates the original image, applies two minimal Easy-Setup
compatibility patches to its prepared copy, and creates:

- `boot1.rom`: flash offsets `00000h-2FFFFh` (192 KiB, mapped at `C0000h`)
- `boot0.rom`: flash offsets `30000h-3FFFFh` (64 KiB, mapped at `F0000h`)
- `pc110_bios.bin`: the complete flash image for direct DDR loading
- `pc110_font.bin`: optional 1 MiB Japanese font image

The prepared 256 KiB image has SHA-256
`e906af0cb235ef490b9d5d24eab300bcf865bd112dd8a096bdf1890816933eaa`.
The patches route the CMOS setup request directly to the IBM loader and replace
the loader's SMM-dependent configuration unlock with the equivalent direct
port write. The original input ROM is never modified.

## Build

MiSTer documents Quartus 17.0.2 as the supported toolchain. The included
script uses a reproducible MiSTer Quartus container:

```sh
scripts/test.sh
scripts/build.sh
```

Override `DOCKER_BIN`, `DOCKER_CONTEXT`, or `QUARTUS_IMAGE` if necessary.
The final bitstream is copied to `artifacts/PC110.rbf`.

## Install

With key-based SSH access to a MiSTer:

```sh
MISTER_HOST=root@192.168.1.74 scripts/deploy-mister.sh
```

The script installs a timestamped RBF in `/media/fat/_Computer`, stages all
ROM assets under `/media/fat/games/PC110`, and creates remembered FC6/FC7
paths for the complete font and BIOS images.

The core identifies itself as `PC110` everywhere: the OSD title, the config
directory, `/tmp/CORENAME`, and the ROM search path (`games/PC110`).
The deployed bitstream is named `IBM PC110_<timestamp>.rbf`, so MiSTer's core
browser shows the full machine name while the internal `PC110` identifier
continues to select the existing x86 support and configuration paths.

MiSTer Main currently activates its shared x86 services (IDE image mounting,
CMOS and boot-ROM loading) from a machine table. The reviewable series in
`scripts/main-patches` adds a distinct `X86_PROFILE_PC110`, makes explicit
machine geometry authoritative, and completes the generic ATA commands used by
the IBM BIOS.

Apply the series to a clean current Main checkout, then build it with the
official toolchain container:

```sh
scripts/apply-main-patches.sh /path/to/Main_MiSTer

docker run --rm --platform linux/arm \
  -v "/path/to/Main_MiSTer:/mister" -w /mister \
  misterkun/toolchain sh -lc \
  "make BASE=arm-linux-gnueabihf \
    CC='arm-linux-gnueabihf-gcc -mcpu=cortex-a9 -mfpu=neon -mfloat-abi=hard'"
```

The complete flash load is not redundant.  Main's normal `boot1.rom` path
historically loads only part of the image, while early PC110 POST needs all
256 KiB at `C0000h-FFFFFh`.  FC7 writes the full image directly to DDR at
`300C0000h`; the split images overlay the same bytes.

The PersonaWare disk's original EMM386 configuration requests an EMS page
frame that overlaps the PC110 upper-memory map and pauses on every boot.
Patch a copy of that VHD to use EMM386 as an XMS/UMB provider without EMS:

```sh
scripts/patch-personaware-noems.sh /path/to/Personaware-disk.vhd
```

The helper creates a `.pre-noems` backup before changing `CONFIG.SYS`.

## Using the core

- Select the timestamped PC110 core in `_Computer`.
- Press `Win+F12` for the PC110 OSD.
- Mount a raw VHD at IDE 0-0 if the BIOS gets as far as boot selection.
- Use Reset after changing storage.

The verified hardware milestone is a zero-error POST, IBM Easy-Setup with
working keyboard navigation, and an unattended PC DOS J7.0/V boot into the
PersonaWare V1.0 desktop. Remaining device-level work is tracked in
[docs/STATUS.md](docs/STATUS.md).

## Source layout

- `PC110.sv` — MiSTer top level and PC110 configuration string
- `docs/ARCHITECTURE.md` — standalone-core and reused-IP boundary
- `rtl/pc110/pc110_chipset.sv` — board-specific I/O and shadow registers
- `rtl/pc110/pc110_host_bridge.v` — shared x86 service transport
- `rtl/cache/l2_cache.v` — 20 MiB boundary, upper-memory write protection,
  and font-window remap
- `rtl/soc/rtc.v` — PC110 CMOS translation
- `sim/pc110_chipset_tb.sv` — self-checking chipset/unlock simulation
- `scripts/` — ROM preparation, test, build, and reversible deployment

## Provenance and licensing

Some CPU and platform RTL derives from
an [upstream 486 project](https://github.com/alfikpl/ao486). It remains under
its original license and attribution; see [LICENSE](LICENSE) and source-file
headers. No IBM firmware is included.
