# MiSTer Main integration

This generic patch applies to MiSTer-devel/Main_MiSTer commit
`c633d2246078d37864bcd2c3fcf68725f7c1ca73`:

1. `0001` completes generic ATA diagnostic, seek, standby-immediate and
   read-verify command responses used by system BIOSes.
2. `0002` adds the optional PC110 F500h PCMCIA mailbox service. It dynamically
   loads a user-installed ARS `libarsusb4.so` and does not contain or link any
   vendor firmware or library. When the vendor exposes I/O but not attribute
   memory, the service can present an optional packed `cis.hex` tuple stream
   and shadow the card configuration registers locally.

PC110 advertises the existing `AO486` x86 service identity. The optional
PCMCIA service recognizes the PC110 by its mailbox signature, so no machine
profile or core-name fork is required. Main's standard VHD
metadata parser supplies disk geometry from a same-basename `.cfg`, so this
patch contains no PC110 name, machine profile or geometry override.

Apply the series to a clean Main checkout:

```sh
scripts/apply-main-patches.sh /path/to/Main_MiSTer
```

The patch is kept in reviewable form while
[Main_MiSTer#1252](https://github.com/MiSTer-devel/Main_MiSTer/pull/1252)
is under review. The former scaler build patch was merged upstream as
[Main_MiSTer#1253](https://github.com/MiSTer-devel/Main_MiSTer/pull/1253).
