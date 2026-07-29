# Architecture and dependency boundary

PC110 is a standalone MiSTer machine core. Its core name, project files,
configuration, ROM directory, chipset policy, memory map and release artifact
are all PC110-specific.

## PC110-owned implementation

- `PC110.sv` and the Quartus `PC110.*` project files
- `rtl/pc110/pc110_chipset.sv`
- `rtl/pc110/pc110_host_bridge.v`
- PC110 flash, font, shadow-memory and 20 MiB memory mapping
- PC110 CMOS values, Easy-Setup entry and machine-specific storage profile
- PC110 simulations, ROM preparation and deployment

## Reused open-source implementation

The core retains the ao486-compatible CPU under `rtl/ao486` and reuses parts
of the MiSTer ao486 PC platform under `rtl/cache`, `rtl/common` and `rtl/soc`.
These are implementation dependencies, not runtime dependencies on the AO486
core. Their original licensing, history and attribution are preserved.

Inherited devices are replaced incrementally as PC110 hardware behavior is
measured. In particular, the current VGA and audio paths are compatibility
implementations rather than complete Chips & Technologies F65535 and ESS
ES488 models.

## MiSTer Main boundary

The host bridge uses Main's shared x86 DMA protocol for floppy, IDE, CMOS and
boot-ROM service. Main integration is represented by the reviewable patch
series in `scripts/main-patches`.

The PC110 patch adds a distinct `X86_PROFILE_PC110`; it does not rename PC110
to AO486 or access `games/AO486` or `config/AO486.*`. Machine-specific disk
geometry is selected by the PC110 profile. Generic IDE protocol fixes are
kept in separate patches for upstream review.

Longer term, Main's name-to-profile table could be replaced by a capability
declared by the core. That would improve extensibility, but it is not necessary
for PC110 to remain a distinct machine.
