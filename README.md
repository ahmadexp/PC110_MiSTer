# IBM Palm Top PC 110 for MiSTer

A MiSTer core for the IBM Palm Top PC 110, the pocketable 486 PC that IBM sold
in Japan in 1995. It combines MiSTer's established x86 CPU and PC-compatible
devices with a PC110-specific chipset, memory map, flash layout and storage
profile.

And it boots. The core gets through the real IBM BIOS POST with no errors, runs
IBM Easy-Setup, and takes PC DOS J7.0/V all the way into the PersonaWare
desktop with the keyboard and Japanese text working. Still a work in progress
though, not every chip on the planar is modelled cycle-for-cycle. See
[docs/STATUS.md](docs/STATUS.md) for what's verified and what's left.

## MiSTer submission

Submitted for official MiSTer inclusion on July 29, 2026 and awaiting
maintainer review. The required Main integration is tracked in
[MiSTer-devel/Main_MiSTer#1252](https://github.com/MiSTer-devel/Main_MiSTer/pull/1252);
the full validation record is in [docs/SUBMISSION.md](docs/SUBMISSION.md).

## What works

* 486SX (no FPU) at a fixed 30 MHz, which is the closest match to the real
  machine I've been able to pin down so far
* 20 MB RAM (4 MB on the planar plus the 16 MB expansion card)
* the full 256 KB PC110 flash mapped at C0000-FFFFF
* VL82C420/SCAMP config ports and their unlock sequences
* PCMCIA register file, font-ROM banking with the 1 MB Japanese font image,
  the inking port and both EC windows
* IDE, floppy, VGA, keyboard and mouse through the shared PC-compatible blocks
* COM1/internal-modem transport through MiSTer Main, with a PC110-specific
  19,200-baud profile
* PC110 CMOS layout

Most of this came from prodding real hardware (the Open-Source-PC110 captures)
and disassembling the BIOS, cross-checked against the PC110-EMU emulator. I use
PC110-EMU as a reference, not something to copy from: its interpreter takes
shortcuts that aren't how the hardware actually behaves, so anything that
mattered got checked on the metal.

## Screenshots

IBM Easy-Setup, running straight off the flash image with working keyboard
navigation:

![Easy-Setup](docs/images/ibm-pc110-easy-setup.png)

PersonaWare V1.0 after an unattended boot:

![PersonaWare](docs/images/ibm-pc110-personaware.png)

## ROMs

No IBM firmware ships with this repo, you supply your own dump.

You need the PC110 BIOS flash (IBM 39H4551, 262144 bytes):

    SHA-256  232101c88466f311bcc32fbc215a4d7569f695ce19f9c07ca67ce2aee5232312

and optionally the 1 MB Japanese font ROM. Run them through:

    scripts/prepare-roms.sh /path/to/pc110_bios.bin /path/to/MSM538032E@SOP44.BIN

That validates the input, makes a working copy with two small Easy-Setup
patches, and writes out `boot0.rom`, `boot1.rom`, the full `pc110_bios.bin`, and
`pc110_font.bin`. Your original dump is never modified.

The two patches only touch the copy: one routes the setup key straight to the
IBM loader, the other swaps an unavailable SMM call for the equivalent direct
port write.

## Building

Quartus 17.0.2 in the raetro container, same as the rest of the cores:

    scripts/test.sh
    scripts/build.sh

The bitstream ends up in `artifacts/PC110.rbf`. Set `DOCKER_BIN`,
`DOCKER_CONTEXT` or `QUARTUS_IMAGE` if your setup needs it. There's a
hardware-tested build under [releases/](releases) if you'd rather not compile.

## Installing

Copy the RBF into `_Computer` and drop `pc110_bios.bin` (and `pc110_font.bin`
if you have it) into `games/PC110`. If you can SSH into your MiSTer this does
the lot:

    MISTER_HOST=root@mister.local scripts/deploy-mister.sh

The core calls itself `PC110` everywhere: OSD title, config dir, `/tmp/CORENAME`
and the ROM path (`games/PC110`). The deploy script timestamps the RBF; rename
it to `IBM PC110_<date>.rbf` if you want the full name in the core browser, the
internal `PC110` id doesn't change.

### Main patch

You need a patched Main for now. Stock Main only switches on its x86 services
(IDE mounting, CMOS, ROM loading) for cores it recognises by name, and it
doesn't know PC110. The series in `scripts/main-patches` adds a PC110 profile,
makes the machine geometry authoritative, and fills in a couple of generic ATA
commands the IBM BIOS leans on. It's up for review as
[Main_MiSTer#1252](https://github.com/MiSTer-devel/Main_MiSTer/pull/1252).

    scripts/apply-main-patches.sh /path/to/Main_MiSTer

then build Main the usual way in the arm toolchain container.

## Notes

* WIN+F12 opens the PC110 OSD. Plain F12 passes through as a normal PC key.
* Mount a raw VHD at IDE 0-0 for the hard disk, and hit "Reset and apply HDD"
  after you change disks.
* Loading the whole flash isn't redundant. Main's usual `boot1.rom` path only
  loads part of the image, but early PC110 POST wants all 256 KB up at
  C0000-FFFFF, so FC7 writes the full image to DDR and the split ROMs overlay
  the same bytes.
* The PersonaWare disk's stock EMM386 line asks for an EMS page frame that sits
  on top of the PC110 upper-memory map and stops for a keypress on every boot.
  `scripts/patch-personaware-noems.sh` flips it to XMS/UMB only (it keeps a
  `.pre-noems` backup).

## Credits and license

The CPU and platform RTL come from the ao486 core (originally Aleksander Osman,
reworked for MiSTer by Sorgelig); those files keep their upstream licenses and
attribution. Everything PC110-specific is GPL-3.0-or-later. See
[LICENSE](LICENSE), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the
per-file headers. No IBM firmware is included.
