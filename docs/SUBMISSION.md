# MiSTer submission record

This document records the reproducible checks for proposing PC110 as an
official MiSTer core. It does not include or authorize redistribution of IBM
firmware.

## Repository requirements

- public source repository with GPL-compatible licensing
- standard root project files: `PC110.qpf`, `PC110.qsf`, `PC110.srf`,
  `PC110.sdc`, `PC110.sv`, `files.qip`, and `clean.bat`
- current MiSTer framework under `sys`
- synthesizable core RTL under `rtl`
- dated release bitstream under `releases`
- browser-visible release name: `IBM PC110_<date>.rbf`
- standard x86 service identity and Home folder: `AO486` / `games/ao486`
- no IBM BIOS, font ROM, operating-system image, or VHD tracked or released
- self-checking chipset testbench in GitHub Actions

The framework migration is based on MiSTer-devel/Template_MiSTer commit
`69b8a2acc6d84dd313b5abcba6a17155287ed3d8`. The Main patch series is based
on MiSTer-devel/Main_MiSTer commit
`c633d2246078d37864bcd2c3fcf68725f7c1ca73`.

Run the local checks with:

```sh
scripts/test.sh
scripts/check-release.sh
```

## Main integration

The core advertises Main's standard `AO486` x86 service identity, so stock Main
provides IDE mounting, CMOS injection and boot-ROM loading without any
PC110-specific profile. Disk geometry is image-owned metadata: a 4 MiB PC110
VHD has a same-basename `.cfg` containing `HEADS=2`, `SECTORS=32`, and
`CYLINDERS=128`.

The remaining upstream work is generic and not required to identify the core:

- [Main_MiSTer pull request 1252](https://github.com/MiSTer-devel/Main_MiSTer/pull/1252)
- [merged independent Main build fix 1253](https://github.com/MiSTer-devel/Main_MiSTer/pull/1253)

Pull request 1252 adds ATA diagnostic/read-verify behavior useful to system
BIOSes. Pull request 1253 is an already-merged independent legacy-toolchain
build fix. Neither change selects PC110 geometry or adds a PC110 name to Main.

## Hardware acceptance evidence

The release candidate is tested on two independent DE10-Nano MiSTer systems.
Both systems must report `/tmp/CORENAME` as `AO486`, complete IBM BIOS POST
without an EBDA error, and reach the PersonaWare desktop from the same release
RBF. Native screenshots and local build reports are retained as test artifacts;
only redistributable screenshots are committed.

Release `PC110_20260729.rbf` passed this regression on both systems. Its
SHA-256 is
`468ef3fd5fc7d8dc0e4224eb8b99633075a782cb083ada025633a21b7b2cb332`.
The full Quartus 17.0.2 build completed with worst setup slack `+0.361 ns`,
worst hold slack `+0.252 ns`, and zero TNS in every reported domain. Both
boards reported `/tmp/CORENAME=AO486`, EBDA error count/code `00h/0000h`, and
reached PersonaWare using the 2/32/128 VHD metadata.

## Maintainer handoff

After Main integration and core review:

1. Follow the official
   [Contributing a Core to MiSTer FPGA](https://github.com/MiSTer-devel/Wiki_MiSTer/wiki/Contributing-a-Core-to-MiSTer-FPGA)
   process and contact the new-core maintainers.
2. Transfer the repository to `MiSTer-devel` when requested.
3. Add the core to the MiSTer Cores wiki page.
4. Coordinate downloader/database metadata so the release artifact and
   required user-supplied ROM names are unambiguous.
