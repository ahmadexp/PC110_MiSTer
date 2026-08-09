IBM PC110 MISTER-READY PACKAGE
==============================

This package installs the hardware-verified IBM PC110 core and the current
PersonaWare English 2.0.6 disk image onto a standard MiSTer SD card.

INCLUDED

  * IBM PC110_20260808.rbf
  * PersonaWare English 2.0.6 as Personaware-disk.vhd
  * Matching 2-head, 32-sector, 128-cylinder image metadata
  * A backup-first MiSTer installer
  * ROM preparation and AO486-to-PC110 migration tools
  * Licenses, notices, and SHA-256 manifests

NOT INCLUDED

IBM PC110 BIOS and font ROM files are not included. Supply dumps from hardware
you own. The required prepared filenames are:

  /media/fat/games/PC110/pc110_bios.bin
  /media/fat/games/PC110/pc110_font.bin       optional Japanese font ROM
  /media/fat/games/PC110/boot0.rom
  /media/fat/games/PC110/boot1.rom

Run tools/prepare-roms.sh on a macOS or Linux computer to validate your dumps
and produce those files. Copy them into /media/fat/games/PC110 before or after
running the installer. Running the installer again safely configures ROMs that
were added later.

INSTALLATION

1. Extract this entire directory onto the MiSTer SD card or copy it to MiSTer.
2. Make sure MiSTer has network or local terminal access.
3. From MiSTer Linux, run:

     cd /path/to/IBM-PC110-MiSTer-Ready-20260808
     sh install.sh

The installer verifies every payload file, switches MiSTer to its menu, backs
up any replaced core, VHD, metadata, or ROM selector under
/media/fat/backup/IBM-PC110-<timestamp>, then installs through temporary files
and atomic renames.

USING THE CORE

Open IBM PC110 under Computers. The internal service name and Home directory
are PC110, while Main reuses its standard x86 implementation. This keeps PC110
ROMs, disks, OSD state and UART settings separate from AO486. The installer
preselects Personaware-disk.vhd at IDE 0-0 on a new installation.

This core requires a MiSTer Main version containing Main_MiSTer#1272. The
installer checks Main before changing any files and stops safely if the PC110
x86 variant is unavailable.

The included VHD already uses its native 2/32/128 CHS layout. Do not apply its
metadata file to an unrelated disk image. Incorrect CHS values can hide or
damage partitions.

VERIFIED COMPONENTS

Core SHA-256:
  19df353c0986874ddf2abbd7cd1163292712f04a4283a6e104d7a16080b37e9c

PersonaWare English VHD SHA-256:
  bb080741f5aac4a6cf9a47672a496c64ab4e332cd7e8535ce9d658e5707867e0

The core completed IBM BIOS POST with error count 00 and first error 0000 on
two DE10-Nano MiSTer systems. PersonaWare English 2.0.6 also completed its
independent release verification.

NOTICES

The FPGA core source and licenses are at:
  https://github.com/ahmadexp/PC110_MiSTer

PersonaWare English is maintained separately at:
  https://github.com/ahmadexp/Personaware-English

The PersonaWare disk image contains IBM software and is not covered by the
FPGA core's GPL license. Review THIRD_PARTY_NOTICES.md before distribution or
use.
