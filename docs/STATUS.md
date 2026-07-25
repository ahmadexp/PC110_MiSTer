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
| CPU | inherited | ao486 no-FPU core; use the 30 MHz setting as the closest current PC110 timing profile |
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
7. The ao486 30 MHz profile is the closest currently available setting; a
   separately verified 33.333 MHz CPU/timer profile remains future work.

## Verification

`scripts/test.sh` checks the board-specific register decode, unlock sequences,
writable PCIC state, font controls, and upper-memory shadow decode with
Icarus Verilog.  Quartus compilation is the integration check for the inherited
ao486 tree.  Hardware smoke tests should record:

- RBF path and SHA-256
- MiSTer Main version
- `/tmp/CORENAME`
- installed ROM sizes and hashes
- on-screen POST code or failure point

The next useful diagnostic is a small FPGA POST logger for writes to the
known BIOS diagnostic ports, exposed to the HPS without changing CPU timing.
