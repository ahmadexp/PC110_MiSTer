# PC110 MiSTer bring-up status

## Evidence used

The board model is based on the local PC110 research repositories:

- `PC110-EMU`: BIOS execution traces and software-observed I/O behavior
- `Open-Source-PC110`: live chipset, Pluto, memory, and peripheral captures
- `Reverse-Engineering-PC110`: BIOS mapping, POST, and disassembly work
- `PC110-SeaBIOS`: previous firmware bring-up and device assumptions

Where those sources conflict, a repeatable live capture wins over the emulator.
Two important corrections follow from that rule:

- `ECh/EDh` is the VL82C420 shadow/cache/ROM configuration bank, not the
  PC110 power-controller mailbox.
- port `4Fh` is an I/O-delay target.  It is not an extended CMOS index port.

## Current hardware model

| Area | State | Notes |
|---|---|---|
| CPU | inherited | 486SX-compatible no-FPU core; PLL power-on and runtime selection are fixed at 30 MHz, the closest characterized PC110 timing |
| RAM | implemented | 20 MiB CPU-visible boundary |
| BIOS flash | implemented for bring-up | complete 256 KiB image at `C0000h-FFFFFh`; shadow RAM currently shares the same DDR backing |
| VL82C420 gates | implemented | observed SCAMP, block-2, and EC/ED unlock sequences |
| ROM shadow protection | implemented | write enable per 16 KiB upper-memory block |
| CMOS | implemented | floppy/equipment/base/extended-memory fields plus checksum |
| PCMCIA | register skeleton | two empty sockets, PCIC identity and writable ExCA registers; no cards or IRQ routing |
| font ROM | implemented | 1 MiB DDR image, banked 8 KiB window |
| inking | minimal | idle/status behavior needed for enumeration only |
| EC-A / EC-B | captured defaults | not a functional power-management microcontroller |
| VGA | inherited placeholder | PC-compatible VGA, not yet C&T F65535 register-accurate |
| audio | inherited placeholder | SB/OPL-compatible path, not yet an ES488 DSP-2.01 identity |
| storage | inherited | PC-compatible IDE/floppy path; PC110 BIOS compatibility still to be proven |

## Known architectural debt

1. ROM and shadow RAM need separate backing if warm resets must preserve an
   immutable flash image after POST has rewritten upper memory.
2. The VL82C420 reset defaults are reconstructed from live post-boot captures,
   not yet proven against a power-on bus trace.
3. The C&T F65535 has PC110-specific mode and power registers that the inherited
   VGA does not expose.
4. EC-A, EC-B, battery, suspend/resume, and the jog/inking path need state
   machines based on firmware traces rather than static bytes.
5. PCMCIA windows, card insertion, interrupts, and DMA are not connected.
6. ES488 mixer/DSP identification and exact IRQ/DMA behavior remain to be
   added on top of the inherited sound path.
7. The fixed 30 MHz profile is the closest currently available setting; a
   separately verified 33.333 MHz CPU/timer profile remains future work.

## Core identity and Main support

The core identifies itself as `PC110`. MiSTer Main supplies a shared x86
transport for IDE image mounting, CMOS injection and boot-ROM loading. The
series in `scripts/main-patches` adds a distinct `X86_PROFILE_PC110`.
Machine-specific geometry is isolated in the profile, while the IDE behavior
corrections are separate generic patches suitable for upstream review.

A December 2024 upstream prefetch-reset correction (`be9b103`) is retained in
`rtl/ao486/memory/prefetch.v`.

## Verification

`scripts/test.sh` checks the board-specific register decode, unlock sequences,
writable PCIC state, font controls, and upper-memory shadow decode with
Icarus Verilog.

`scripts/sim-post.sh` executes the real 256 KiB flash image from the reset
vector on the full memory path (486SX CPU, iobus, pc110_chipset, the modified
l2_cache, and a latency/backpressure DDR model) and traces all I/O, memory
writes, flag changes, and executed EIPs.  Findings from that harness:

- the BIOS reset code performs a severe CPU register/segment/flags self-test
  at `F000:44CA-4648`; any failure silently halts at `F000:461A` (or writes
  POST code `DDh` to ports `190h/191h` and halts at `F000:44D9`)
- the BIOS reports POST progress bytes on port `3BCh` (`C1h`, `05h`,
  `C2h`, ...) and failure codes on `190h/191h`
- in simulation the CPU passes the self-test, the chipset answers the full
  VL82C420 unlock/config sequence, and POST reaches the memory-sizing
  phase (BDA writes at `410h` onward) under every configuration tested:
  L1 on/off, with/without the prefetch fix, ideal and slow DDR

The POST-code logger grew into a full serial trace (UART `/dev/ttyS1` on the
HPS at 115200): POST checkpoints (`190h`), progress (`3BCh`), the complete
8042 conversation (commands, status, data), the ATA task file, CMOS reads,
and an L2 snoop of the EBDA POST-error-log writes - all interleaved in
stream order.  `scratchpad` tooling (`cap.sh` / `decode_plog.py` in the
session workspace) reloads the core, captures a POST, and decodes it.

## Boot milestone (2026-07-28)

POST completes with **zero errors**, INT19 loads the boot sector from the
Personaware disk image, and **PC DOS J7.0/V boots to a working `C:\PW>`
prompt with a fully functional keyboard** (typed commands execute).

The final blocker was keyboard POST error 301 - five stacked causes, found
with the interleaved trace plus live-BIOS disassembly grounded at exact
ROM offsets:

1. keyboard identify must return the TRANSLATED ID `AB 41` (BIOS checks
   `41h` at `F000:B068`), not raw `AB 83`
2. the 8042's single shared output buffer: AUXOBF (status bit5) must be
   `status_mousebufferfull` (respecting aux-disable), not raw mouse-FIFO
   occupancy, or stale mouse data marks keyboard ACKs as mouse bytes
3. the input buffer (IBF) must free as soon as a device command is
   consumed; gating it on OBF made the BIOS's aux-disable command-byte
   write (`65h`) silently drop, wedging the mouse into the shared buffer
4. device FIFOs are cleared on each new device command so responses are
   exactly aligned (`FFh` -> precisely `FA AA`); stray hps_io power-on BAT
   bytes otherwise read as "keyboard jabber"
5. the EARLY keyboard test (checkpoint `56h`, `F000:4FEF`) is skipped via
   the BIOS's own gate (8042 status bit4 = inhibited, asserted only inside
   the `56h`-`5Ah` checkpoint window): its pass path ends in a stuck-key
   check that consults the system MCU through an SMI API (`AX=5380h`)
   whose result returns in CPU registers rewritten by SMM - the CPU core has no
   SMM, so the check fails deterministically.  The MAIN keyboard test
   (checkpoint `6Dh`) still runs with bit4=1 and passes.

A local aux/mouse responder answers the pointing-device reset
(`FF -> FA AA 00`, identify `F2 -> FA 00`); mouse POST messages are
display-only and never gate boot.

## PersonaWare milestone (2026-07-28, evening)

**PersonaWare V1.0 runs.**  One root cause unlocked the whole Japanese
stack: \$FONT.SYS verifies the hardware font ROM with a write-ignore
probe, so the banked font window is now write-protected (and its decode
no longer aliases every 1 MiB).  With fonts registering, \$DISP.SYS
installs V-text, DOSPM's INT15 AX=5000h probe passes (its ERROR 5 was
exactly that probe failing), and the full PersonaWare desktop appears
with correct Kanji, working keyboard (F1 opens its Help), and the RTC
clock right.  A second display blocker fell with it: the Input Status 1
shim forced bit0=1, deadlocking \$DISP.SYS's interrupts-off wait for
active display after its mode-12h set - 3DAh/3BAh are no longer shimmed
and the implemented VGA status answers.

Easy-Setup entry: the BIOS's F1 gate reads the held key from the system
MCU via SMI (un-emulatable), but the same INT19 decision first tests
CMOS 7Bh bit3.  The OSD "Enter BIOS Setup" action (and any real F1 press
during POST) forces that bit via rtc setup_req; the request is one-shot,
consumed at the INT19 read (checkpoint-gated 6Eh-7Fh - POST emits HIGH
checkpoint codes early, so a plain >= compare mis-fired).  The OSD items
themselves were dead until now: reset-style CONF_STR entries take ONE
index char ("R42"/"R41" parsed as bit 4 + junk); they are rF/rG =
status[47]/[48].  The divert is trace-verified (7Bh read returns 0x0A,
one-shot clears).  The interactive setup UI is a separate 128 KiB flash
module the loader (F000:DD5D) copies through a flash-window remap - now
modeled (easysetup_remap: eced 11h/12h zero + planar-control bit2, L2
aliases E/F reads to the module's DDR copy at C0000h) plus CMOS 7Eh/7Fh
pointing the loader's INT15 5380h unlock at the config bank.

Both test units run the same full-effort build (worst slack -0.233 ns).
Unit 2's black graphics screen was an OLD patched-Main binary, not the
core - Main is synced between units now (backup MiSTer.bak-20260729).

## Final setup and boot polish (2026-07-28, hardware verified)

**IBM Easy-Setup is interactive.** The setup request already reached the INT19
decision (`CMOS 7Bh = 0Ah` once, then `02h` after one-shot consumption), but
two firmware paths still depended on PC110 system-management behavior absent
from the current CPU/platform implementation. `scripts/prepare-roms.sh` now
applies two size-preserving patches
to the validated IBM image:

- `F000:8145` changes `jnz 815Bh` to `jnz 817Ch`, routing CMOS bit 3 directly
  to the existing Easy-Setup loader
- the relocated stub at `F000:DDE6` replaces its initial
  `INT 15h AX=5380h` unlock with the equivalent direct `out 00FBh,80h`

MiSTer Main actually executes the split `boot0.rom`/`boot1.rom`, so these are
generated from the patched copy as well as `pc110_bios.bin`. On unit
On the primary test MiSTer, the serial trace showed `ECED[11]=00h` and
`ECED[12]=00h`,
followed by their restoration. The real IBM Easy-Setup home page appeared,
and Right Arrow moved selection from Config to Date/Time.

**The EMM386 keypress pause is gone.** Open-bus data (`FFh`) still looks like
ROM to EMM386, so the earlier CC000h-DBFFFh experiment could not solve the
warning. The PersonaWare disk now uses:

```text
DEVICE=C:\DOS\EMM386.EXE NOEMS
```

The original disk is retained on the test unit as
`Personaware-disk.pre-noems.vhd`. An unattended cold boot reached PersonaWare
in under 30 seconds with EBDA POST error count/code `00h/0000h`; DOS/V,
Japanese fonts, UMB-loaded drivers, keyboard, and the desktop remained
functional. `scripts/patch-personaware-noems.sh` makes the disk edit
reproducible and creates a backup before writing.

Hardware evidence:

- prepared BIOS SHA-256:
  `e906af0cb235ef490b9d5d24eab300bcf865bd112dd8a096bdf1890816933eaa`
- patched boot0 SHA-256:
  `b06ef449802ad310fcbf17aa5aa2df2677d394ab01a09cfb3d815f095a2a7aca`
- patched PersonaWare VHD SHA-256:
  `625a377d45efa98b8ef5506b91fbbc9c4899938d6dbd500203a7a794f913eba4`
- release RBF SHA-256:
  `aa0ed49ef09e1d6745e595034064f3f780c891f2a225de6867e1c202f412253e`
- full Quartus timing build: worst setup slack `+0.410 ns`, worst hold slack
  `+0.245 ns`, and zero TNS in every reported domain
- current patched Main SHA-256:
  `b784bf841164c7254da6b7ac0de0964a9d113f7e28ea76318d25df0edc8a6398`
- 29 July 2026 hardware verification on two DE10-Nano MiSTer systems: both
  reported `CORE=PC110`, EBDA error count/code `00h/0000h`, and booted
  PersonaWare with working storage and video
- current MiSTer framework release verified on both boards: each on-device RBF
  matched the release SHA, reported `CORE=PC110`, and reached PersonaWare at
  native 640x480
- a PID change after `/dev/MiSTer_cmd` `load_core` is expected: current Main
  deliberately restarts itself after loading any RBF via `app_restart()`

Known follow-ups:

- the trackpad is not yet relayed to the HPS mouse (the serial relay held
  IBF and broke POST; needs a copy-register relay that does not pin IBF)
- RAM-size OSD menu (4/8/12/20 MB) still to be added
- the optional POST UART trace is disabled in release builds; enable the
  chipset's `POSTLOG_ENABLE` parameter only for hardware bring-up

Hardware smoke tests should record:

- RBF path and SHA-256
- MiSTer Main version
- `/tmp/CORENAME`
- installed ROM sizes and hashes
- EBDA error count/code and a native MiSTer screenshot
- for diagnostic builds only, the serial POST trace
