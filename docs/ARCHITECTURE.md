# Architecture and dependency boundary

PC110 is a standalone MiSTer machine core. Its project files, chipset policy,
memory map and browser-visible release artifact are PC110-specific. It uses the
standard AO486 service identity at the MiSTer Main boundary.

## PC110-owned implementation

- `PC110.sv` and the Quartus `PC110.*` project files
- `rtl/pc110/pc110_chipset.sv`
- `rtl/pc110/pc110_host_bridge.v`
- PC110 flash, font, shadow-memory and selectable 4/8/12/20 MiB memory mapping
- PC110 CMOS values, Easy-Setup entry and image-declared storage geometry
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
boot-ROM service. The `CONF_STR` service identifier is `AO486`, while the RBF
filename remains `IBM PC110_<date>.rbf` for the core browser. Main therefore
needs no PC110 name, profile or geometry branch.

Hard-disk geometry belongs to the mounted image. When needed, a same-basename
`.cfg` supplies `HEADS`, `SECTORS`, and optionally `CYLINDERS` through Main's
existing VHD metadata parser. These values must describe the geometry already
encoded in the image's partition table and BPB; they must not replace it. The
optional patch in `scripts/main-patches` is a generic IDE correction kept
separate for upstream review.
