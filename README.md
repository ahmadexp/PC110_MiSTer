# IBM Palm Top PC 110 for MiSTer

[![RTL tests](https://github.com/ahmadexp/PC110_MiSTer/actions/workflows/test.yml/badge.svg)](https://github.com/ahmadexp/PC110_MiSTer/actions/workflows/test.yml)
![Quartus](https://img.shields.io/badge/Quartus-17.0.2-blue)
![Target](https://img.shields.io/badge/target-DE10--Nano%20%2F%20MiSTer-orange)

This repository is an FPGA bring-up of the IBM Palm Top PC 110, built on the
MiSTer ao486 core.  It is deliberately based on the 26 March 2022 ao486 source
(`1c5cbe5301f2ba87e6db6e3de52dc7536a1eac35`) so that the resulting RBF remains
compatible with the older MiSTer Main binary on the development machine.

This is an engineering core, not yet a cycle-exact replacement for the whole
PC110 planar.  The current milestone gets the real 256 KiB IBM flash image in
front of a 486 CPU and implements enough of the board-specific decode to begin
real POST on hardware.  See [docs/STATUS.md](docs/STATUS.md) for the measured
and placeholder parts.

## What is implemented

- ao486 486-class CPU, AT peripherals, IDE, floppy, VGA, keyboard, and mouse
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

The script validates the image and creates:

- `boot1.rom`: flash offsets `00000h-2FFFFh` (192 KiB, mapped at `C0000h`)
- `boot0.rom`: flash offsets `30000h-3FFFFh` (64 KiB, mapped at `F0000h`)
- `pc110_bios.bin`: the complete flash image for direct DDR loading
- `pc110_font.bin`: optional 1 MiB Japanese font image

## Build

MiSTer documents Quartus 17.0.2 as the supported toolchain.  The included
script uses the ao486 project's reproducible Quartus container:

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

The script:

1. makes a timestamped backup under
   `/media/fat/games/AO486/.pc110-backup-*`;
2. installs a timestamped RBF in `/media/fat/_Computer`;
3. stages PC110 assets under `/media/fat/games/PC110`;
4. installs the split ROMs in `/media/fat/games/AO486`; and
5. creates remembered FC6/FC7 paths for the complete font and BIOS images.

The core identifies itself as `PC110` everywhere: the OSD title, the config
directory, `/tmp/CORENAME`, and the ROM search path (`games/PC110`).

MiSTer Main activates its x86 support (IDE image mounting, CMOS) by core
name, and stock Main only recognizes `AO486`.  This repository therefore
carries a one-line patch in `upstream-main/user_io.cpp` that adds `PC110` to
Main's `is_x86()` check.  Build the patched Main with the official toolchain
container and install it alongside the core:

```sh
docker run --rm -v "$PWD/upstream-main:/mister" -w /mister \
  misterkun/toolchain make
```

The complete flash load is not redundant.  Main's normal `boot1.rom` path
historically loads only part of the image, while early PC110 POST needs all
256 KiB at `C0000h-FFFFFh`.  FC7 writes the full image directly to DDR at
`300C0000h`; the split images overlay the same bytes.

To restore the AO486 files later, pass the backup path printed by deployment:

```sh
MISTER_HOST=root@192.168.1.74 \
  scripts/restore-mister.sh /media/fat/games/AO486/.pc110-backup-TIMESTAMP
```

## Using the core

- Select the timestamped PC110 core in `_Computer`.
- Press `Win+F12` for the ao486 OSD.
- Mount a raw VHD at IDE 0-0 if the BIOS gets as far as boot selection.
- Use Reset after changing storage.

At this stage, a successful smoke test means that the FPGA configures, MiSTer
recognizes the core as `AO486`, the direct ROM loads succeed, and the IBM BIOS
begins POST.  Reaching Personaware or booting an operating system depends on
additional PC110 chipset and C&T F65535 work listed in
[docs/STATUS.md](docs/STATUS.md).

## Source layout

- `PC110.sv` — MiSTer top level and PC110 configuration string
- `rtl/pc110/pc110_chipset.sv` — board-specific I/O and shadow registers
- `rtl/cache/l2_cache.v` — 20 MiB boundary, upper-memory write protection,
  and font-window remap
- `rtl/soc/rtc.v` — PC110 CMOS translation
- `sim/pc110_chipset_tb.sv` — self-checking chipset/unlock simulation
- `scripts/` — ROM preparation, test, build, and reversible deployment

## Provenance and licensing

The base is
[MiSTer-devel/ao486_MiSTer](https://github.com/MiSTer-devel/ao486_MiSTer),
which in turn derives from
[alfikpl/ao486](https://github.com/alfikpl/ao486).  The inherited RTL remains
under its original licenses; see [LICENSE](LICENSE) and source-file headers.
No IBM firmware is included.
