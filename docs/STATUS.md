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
| CPU | inherited | ao486 no-FPU core; PLL power-on and runtime selection are both forced to its 30 MHz profile, the closest characterized PC110 timing |
| RAM | implemented | 20 MiB CPU-visible boundary |
| BIOS flash | implemented for bring-up | complete 256 KiB image at `C0000h-FFFFFh`; shadow RAM currently shares the same DDR backing |
| VL82C420 gates | implemented | observed SCAMP, block-2, and EC/ED unlock sequences |
| ROM shadow protection | implemented | write enable per 16 KiB upper-memory block |
| CMOS | implemented | floppy/equipment/base/extended-memory fields plus checksum |
| PCMCIA | register skeleton | two empty sockets, PCIC identity and writable ExCA registers; no cards or IRQ routing |
| font ROM | implemented | 1 MiB DDR image, banked 8 KiB window |
| inking | minimal | idle/status behavior needed for enumeration only |
| EC-A / EC-B | captured defaults | not a functional power-management microcontroller |
| VGA | inherited placeholder | ao486 VGA, not yet C&T F65535 register-accurate |
| audio | inherited placeholder | ao486 SB/OPL path, not yet an ES488 DSP-2.01 identity |
| storage | inherited | ao486 IDE/floppy path; PC110 BIOS compatibility still to be proven |

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
7. The forced ao486 30 MHz profile is the closest currently available setting; a
   separately verified 33.333 MHz CPU/timer profile remains future work.

## Core identity and Main support

The core identifies itself as `PC110`.  MiSTer Main gates its x86 support
(IDE image mounting, CMOS injection, boot-ROM loading) on the core name, so
a patched Main is required; the one-line `is_x86()` change plus a gcc-6
compatibility fix live in `scripts/mister-main-pc110.patch` (apply to the
`upstream-main` tree and build with the misterkun/toolchain container using
`make BASE=arm-linux-gnueabihf CC='arm-linux-gnueabihf-gcc -mcpu=cortex-a9
-mfpu=neon -mfloat-abi=hard'`).

The December 2024 upstream ao486 prefetch-reset fix (`be9b103`) is
cherry-picked into `rtl/ao486/memory/prefetch.v`.

## Verification

`scripts/test.sh` checks the board-specific register decode, unlock sequences,
writable PCIC state, font controls, and upper-memory shadow decode with
Icarus Verilog.

`scripts/sim-post.sh` executes the real 256 KiB flash image from the reset
vector on the full memory path (ao486 CPU, iobus, pc110_chipset, the modified
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
   whose result returns in CPU registers rewritten by SMM - ao486 has no
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
and the real ao486 VGA status answers.

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

Known follow-ups:

- Easy-Setup UI: flash-window remap + unlock built, hardware verification
  pending (setup currently reaches the I9990303 gateway; the icon screen's
  int16 loop treats any key as "retry boot", NOT as setup entry)
- EMM386 warns "Option ROM or RAM detected within page frame" and pauses:
  fixed by open-bussing CC000h-DBFFFh (commit 91d00d0), build pending
- the trackpad is not yet relayed to the HPS mouse (the serial relay held
  IBF and broke POST; needs a copy-register relay that does not pin IBF)
- MiSTer Main crashes and respawns on load_core while the PC110 core runs
  (FPGA keeps running; automation must timeout FIFO writes) - suspect our
  Main patch, not yet investigated
- RAM-size OSD menu (4/8/12/20 MB) still to be added
- the EBDA errlog snoop and 8042/CMOS trace tags are debug aids; strip or
  gate them for a release build

Hardware smoke tests should record:

- RBF path and SHA-256
- MiSTer Main version
- `/tmp/CORENAME`
- installed ROM sizes and hashes
- serial POST trace (`cap.sh`), EBDA error count/code, and a screenshot
