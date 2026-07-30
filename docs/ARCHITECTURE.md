# Architecture and dependency boundary

PC110 is a standalone MiSTer machine core. Its core name, project files,
configuration, ROM directory, chipset policy, memory map and release artifact
are all PC110-specific.

## PC110-owned implementation

- `PC110.sv` and the Quartus `PC110.*` project files
- `rtl/pc110/pc110_chipset.sv`
- `rtl/pc110/pc110_host_bridge.v`
- PC110 flash, font, shadow-memory and selectable 4/8/12/20 MiB memory mapping
- PC110 CMOS values, Easy-Setup entry and machine-specific storage profile
- PC110 simulations, ROM preparation and deployment

## Reused open-source implementation

The core uses a third-party 486SX-compatible CPU under `rtl/ao486` and reusable
PC components under `rtl/cache`, `rtl/common` and `rtl/soc`. These are source
dependencies, not runtime dependencies on another MiSTer core. Their original
licensing, history and attribution are preserved.

Inherited devices are replaced incrementally as PC110 hardware behavior is
measured. In particular, the current VGA and audio paths are compatibility
implementations rather than complete Chips & Technologies F65535 and ESS
ES488 models.

## MiSTer Main boundary

The host bridge uses Main's shared x86 DMA protocol for floppy, IDE, CMOS and
boot-ROM service. Main integration is represented by the reviewable patch
series in `scripts/main-patches`.

The PC110 patch adds a distinct `X86_PROFILE_PC110`. Machine-specific disk
geometry is selected by that profile, and PC110 uses only its own game and
configuration directories. Generic IDE protocol fixes are kept in separate
patches for upstream review.

Longer term, Main's name-to-profile table could be replaced by a capability
declared by the core. That would improve extensibility, but it is not necessary
for PC110 to remain a distinct machine.
