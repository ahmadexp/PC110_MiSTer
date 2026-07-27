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

On hardware the CPU halts before the first BDA write, with junk byte-writes
visible in low DDR - behavior simulation does not reproduce.  The next
diagnostic is a POST-code logger: latch chipset writes to `3BCh`, `190h`,
and `191h` and stream them out the core's UART (`/dev/ttyS1` on the HPS) so
the on-hardware failure point becomes directly observable.

Hardware smoke tests should record:

- RBF path and SHA-256
- MiSTer Main version
- `/tmp/CORENAME`
- installed ROM sizes and hashes
- on-screen POST code or failure point
