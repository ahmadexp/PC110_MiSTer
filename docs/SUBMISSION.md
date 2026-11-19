# MiSTer submission record

This document records the reproducible checks for proposing PC110 as an
official MiSTer core. It does not include or authorize redistribution of IBM
firmware.

## Candidate for new-core review (November 19, 2026)

The requested outcome is acceptance of the PC110 FPGA core into MiSTer-devel,
followed by inclusion in the official distribution and its generated downloader
database. The request was sent to `newcores@misterfpga.org` on November 19,
2026 with the subject "PC110 core submission for MiSTer-devel and official
updater inclusion". Gmail confirmed that the message was sent. Status:
awaiting maintainer review. This record does not indicate acceptance.

- Source: [PC110_MiSTer](https://github.com/ahmadexp/PC110_MiSTer)
- Candidate tag: [v2026.08.08](https://github.com/ahmadexp/PC110_MiSTer/releases/tag/v2026.08.08)
- Candidate source commit: `940f4bb334723893ade47337e8845fde0faf6545`
- Core-only file: `releases/PC110_20260808.rbf` (4,197,600 bytes)
- SHA-256: `19df353c0986874ddf2abbd7cd1163292712f04a4283a6e104d7a16080b37e9c`
- License: GPLv3 with the retained BSD and other upstream notices described in
  `THIRD_PARTY_NOTICES.md`; `releases/LICENSE.txt` accompanies distribution.
- Platform: DE10-Nano MiSTer, using onboard DDR3; no external SDRAM required.

The proposed official artifact excludes the separate convenience ZIP, all
IBM BIOS/font ROMs, operating-system images and VHDs. Users supply their own
firmware and boot media. `scripts/prepare-roms.sh` validates a user-supplied
256 KiB BIOS, prepares the boot-ROM split, and applies two documented
Easy-Setup compatibility patches to a copy. The source dump is unchanged.

### Checks repeated on November 19

- `scripts/test.sh`: chipset tests in normal and diagnostic configurations,
  RAM-module geometry, and AO486-to-PC110 asset migration passed locally.
- `scripts/check-release.sh`: repository layout and firmware exclusion passed.
- The candidate RBF matches its published SHA-256 and GitHub release digest.
- The DE10-Nano project files, `rtl/` and `sys/` in the submission branch are
  unchanged from the candidate tag.
- `sys/` exactly matches Template_MiSTer commit
  `69b8a2acc6d84dd313b5abcba6a17155287ed3d8`; there are no local framework edits.
- The official distribution Main reports `$VER:261010` and includes PC110
  recognition. Its SHA-256 is
  `ba8746d91ced547845b743b7826d827cfd6c488de0bcf8b27112d8d77f8a7e27`.
- The official content collector was run locally for this core. It selected
  only the latest dated RBF, created `games/PC110`, copied the documentation
  and license, and generated the `pc110` computer-core metadata.

These are local regression and packaging checks, not a new synthesis or
hardware boot run. Existing hardware acceptance evidence is summarized below.
Known limitations remain in `docs/STATUS.md`, including incomplete PCMCIA,
system-management, C&T graphics and ES488-specific behavior. Windows 95 and
all original hardware diagnostics are not claimed as verified for this
candidate.

### Proposed official updater metadata

| Field | Value |
|---|---|
| Core display name | IBM PC110 |
| Distribution category | `_Computer` |
| Latest bitstream | `PC110_20260808.rbf` |
| Home directory | `PC110` |
| External SDRAM required | No |
| Filter term | `pc110` |
| Repository | Current public repository above, with the final organization URL to be agreed during review |

The distribution collector reads the official Cores wiki and accepts core
URLs under `MiSTer-devel`. After acceptance and repository onboarding, the
maintainers can add the Computer entry with Home `PC110` and SDRAM `No`.
The existing collector then generates `_Computer/PC110_20260808.rbf`,
`games/PC110`, documentation and downloader metadata. No hand-edited
`db.json.zip` or binary PR against Distribution_MiSTer's main branch is needed.

## Repository requirements

- public source repository with GPL-compatible licensing
- standard root project files: `PC110.qpf`, `PC110.qsf`, `PC110.srf`,
  `PC110.sdc`, `PC110.sv`, `files.qip`, and `clean.bat`
- current MiSTer framework under `sys`
- synthesizable core RTL under `rtl`
- dated release bitstream under `releases`
- distribution release name: `PC110_20260808.rbf`
- x86 service identity and Home folder: `PC110` / `games/PC110`
- no IBM BIOS, font ROM, operating-system image, or VHD tracked in the core
  source or included in the core-only submission artifact
- self-checking chipset, RAM configuration and identity-migration tests

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

The core advertises `PC110` as its x86 service identity. Main pull request
[1272](https://github.com/MiSTer-devel/Main_MiSTer/pull/1272) recognizes that
name as an x86 variant (merged August 9, 2026), retaining Main's standard
IDE mounting, CMOS injection and boot-ROM loading while giving PC110 its
own Home directory and persistent
configuration. Disk geometry remains image-owned: the tested 4 MiB PersonaWare
VHD's MBR and BPB already encode 2 heads and 32 sectors per track, so its
same-basename `.cfg` declares `HEADS = 2`, `SECTORS = 32`, and `CYLINDERS =
128`. Metadata must match an image's existing CHS layout and must not be used
to change it.

The independent ATA diagnostic/read-verify improvement in Main pull request
[1252](https://github.com/MiSTer-devel/Main_MiSTer/pull/1252) remains useful to
system BIOSes, but is separate from the PC110 identity change.

## Hardware acceptance evidence

The release candidate is tested on two independent DE10-Nano MiSTer systems.
Both systems must report `/tmp/CORENAME` as `PC110`, complete IBM BIOS POST
without an EBDA error, and reach the PersonaWare desktop from the same release
RBF. Native screenshots and local build reports are retained as test artifacts;
only redistributable screenshots are committed.

The earlier release `PC110_20260729.rbf` passed this regression on both systems. Its
SHA-256 is
`468ef3fd5fc7d8dc0e4224eb8b99633075a782cb083ada025633a21b7b2cb332`.
The full Quartus 17.0.2 build completed with worst setup slack `+0.361 ns`,
worst hold slack `+0.252 ns`, and zero TNS in every reported domain. Both
boards reported the former `/tmp/CORENAME=AO486` compatibility identity, EBDA
error count/code `00h/0000h`, and
reached PersonaWare using the 2/32/128 VHD metadata.

The public MiSTer-ready convenience bundle is separate from the core-only
submission artifact. It adds the independently maintained PersonaWare English
VHD but still excludes IBM BIOS and font ROM files. MiSTer maintainers can use
the dated RBF and source release without downloading that convenience bundle.

## Maintainer handoff

The official new-core contact is `newcores@misterfpga.org`. The request covers
core review, repository onboarding and the official updater entry together.
Repository transfer and changes to the official Cores wiki follow maintainer
acceptance; neither has been performed as part of preparing this candidate.

After core review:

1. Follow the official
   [Contributing a Core to MiSTer FPGA](https://github.com/MiSTer-devel/Wiki_MiSTer/wiki/Contributing-a-Core-to-MiSTer-FPGA)
   process and contact the new-core maintainers.
2. Transfer the repository to `MiSTer-devel` when requested.
3. Add the core to the MiSTer Cores wiki page.
4. Coordinate downloader/database metadata so the release artifact and
   required user-supplied ROM names are unambiguous.
