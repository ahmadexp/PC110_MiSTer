# MiSTer Main integration

These patches are based on MiSTer-devel/Main_MiSTer commit
`ffcdf1edb52c95705298d2fe23e9737e08b75b65` and are intentionally separated
for upstream review:

1. `0001` makes the existing IDE geometry arguments authoritative. This is a
   generic API correction.
2. `0002` adds `PC110` as an explicit x86 machine profile and gives that profile
   its native two-head, 32-sector disk geometry.
3. `0003` completes two generic ATA command responses required by the IBM BIOS.
4. `0004` fixes a generic `errno` macro collision exposed by MiSTer's legacy
   Main build toolchain.

PC110 uses Main's shared x86 transport with its own profile and policy.

Apply the series to a clean Main checkout:

```sh
scripts/apply-main-patches.sh /path/to/Main_MiSTer
```

The patches are kept as a reviewable series so they can become separate
upstream pull requests.
