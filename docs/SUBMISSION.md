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
- unique non-arcade Home folder: `games/PC110`
- no IBM BIOS, font ROM, operating-system image, or VHD tracked or released
- self-checking chipset testbench in GitHub Actions

The framework migration is based on MiSTer-devel/Template_MiSTer commit
`69b8a2acc6d84dd313b5abcba6a17155287ed3d8`. The Main patch series is based
on MiSTer-devel/Main_MiSTer commit
`ffcdf1edb52c95705298d2fe23e9737e08b75b65`.

Run the local checks with:

```sh
scripts/test.sh
scripts/check-release.sh
```

## Integration dependency

MiSTer Main needs an explicit PC110 machine profile for IDE geometry, CMOS,
and boot-ROM handling. The proposed upstream integration is:

- [Main_MiSTer pull request 1252](https://github.com/MiSTer-devel/Main_MiSTer/pull/1252)
- [independent Main build fix 1253](https://github.com/MiSTer-devel/Main_MiSTer/pull/1253)

The core repository is reviewable independently, but general distribution
should be coordinated with pull request 1252 so a stock Main binary recognizes
the `PC110` core identifier.

## Hardware acceptance evidence

The release candidate is tested on two independent DE10-Nano MiSTer systems.
Both systems must report `/tmp/CORENAME` as `PC110`, complete IBM BIOS POST
without an EBDA error, and reach the PersonaWare desktop from the same release
RBF. Native screenshots and local build reports are retained as test artifacts;
only redistributable screenshots are committed.

Release `PC110_20260729.rbf` passed this regression on both systems. Its
SHA-256 is
`aa0ed49ef09e1d6745e595034064f3f780c891f2a225de6867e1c202f412253e`.
The full Quartus 17.0.2 build completed with worst setup slack `+0.410 ns`,
worst hold slack `+0.245 ns`, and zero TNS in every reported domain.

## Maintainer handoff

After Main integration and core review:

1. Follow the official
   [Contributing a Core to MiSTer FPGA](https://github.com/MiSTer-devel/Wiki_MiSTer/wiki/Contributing-a-Core-to-MiSTer-FPGA)
   process and contact the new-core maintainers.
2. Transfer the repository to `MiSTer-devel` when requested.
3. Add the core to the MiSTer Cores wiki page.
4. Coordinate downloader/database metadata so the release artifact and
   required user-supplied ROM names are unambiguous.
