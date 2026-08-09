# IBM PC110 MiSTer release 2026-08-08

This release gives the core its own `PC110` service identity. MiSTer Main still
uses the standard x86 IDE, CMOS and boot-ROM implementation, while PC110 now
keeps its Home directory, ROM selectors, mounted disks, OSD state and UART
settings separate from other x86 cores.

## Main requirement

The RBF requires a Main version containing
[MiSTer-devel/Main_MiSTer#1272](https://github.com/MiSTer-devel/Main_MiSTer/pull/1272).
The release installer checks for that support before installing the new core.

## Migration

- The PC110 Home directory is `/media/fat/games/PC110`.
- ROM selectors are `/media/fat/config/PC110.f6` and `PC110.f7`.
- Mounted-disk state is `/media/fat/config/PC110sys.cfg`.
- UART configuration uses `uartmode.PC110` and `uartspeed.PC110`.
- The installer copies only explicitly named PC110 assets from an older
  `games/ao486` installation when the new destination is missing. It does not
  alter AO486 files or settings.
- Existing PC110 RBFs and replaced files are copied to a timestamped backup
  before replacement.

Disk geometry remains owned by each image. The included PersonaWare metadata
declares the image's existing 2-head, 32-sector, 128-cylinder CHS layout and
does not rewrite it.

## Artifacts

```text
19df353c0986874ddf2abbd7cd1163292712f04a4283a6e104d7a16080b37e9c  PC110_20260808.rbf
1cc78a3c2da0d87c3b424c81183613015a9864737d8c76e55b5a24ea3f2f5f46  IBM-PC110-MiSTer-Ready-20260808.zip
bb080741f5aac4a6cf9a47672a496c64ab4e332cd7e8535ce9d658e5707867e0  Personaware-disk.vhd
```

IBM BIOS and font ROM files are not included in the public package.
