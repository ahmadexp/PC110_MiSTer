# MiSTer Main integration

The current compatibility patch applies to MiSTer-devel/Main_MiSTer commit
`7b5c8de5d3fb16f9cccc1f274a2ff1b481637e42`:

1. `0002` recognizes the `PC110` core name as an x86 variant, following Main's
   existing PCXT-EGA, Tandy1000 and PCjr variant pattern.

The patch reuses Main's existing x86 implementation. It contains no machine
profile, firmware, disk geometry override or PC110-specific storage behavior.
Main's standard VHD metadata parser continues to obtain geometry from each
image's same-basename `.cfg` when one is required.

Apply the series to a clean Main checkout:

```sh
scripts/apply-main-patches.sh /path/to/Main_MiSTer
```

The patch is kept in reviewable form while
[Main_MiSTer#1272](https://github.com/MiSTer-devel/Main_MiSTer/pull/1272)
is under review. The generic ATA command work was merged upstream as
[Main_MiSTer#1252](https://github.com/MiSTer-devel/Main_MiSTer/pull/1252).
