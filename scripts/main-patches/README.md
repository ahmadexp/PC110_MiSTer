# MiSTer Main integration

This generic patch applies to MiSTer-devel/Main_MiSTer commit
`c633d2246078d37864bcd2c3fcf68725f7c1ca73`:

1. `0001` completes generic ATA diagnostic, seek, standby-immediate and
   read-verify command responses used by system BIOSes.

PC110 advertises the existing `AO486` x86 service identity. Main's standard VHD
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
