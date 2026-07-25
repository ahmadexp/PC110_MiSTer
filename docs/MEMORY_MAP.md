# PC110 memory and MiSTer DDR map

## CPU-visible map used by the core

| CPU address | Size | Function |
|---|---:|---|
| `000000h-09FFFFh` | 640 KiB | conventional RAM |
| `0A0000h-0BFFFFh` | 128 KiB | inherited VGA apertures |
| `0C0000h-0EFFFFh` | 192 KiB | lower three quarters of PC110 flash during early POST; later shadow/VGA use is controlled by VL82C420 registers |
| `0F0000h-0FFFFFh` | 64 KiB | system BIOS; reset vector is at flash offset `3FFF0h` |
| `100000h-13FFFFFh` | 19 MiB | extended RAM, for 20 MiB total |
| selected 8 KiB segment | 8 KiB | banked font-ROM window |

The IBM image is not a conventional 64 KiB system BIOS plus a separate option
ROM.  At reset, its entire 256 KiB flash is linearly decoded over
`C0000h-FFFFFh`.  Its last 16 bytes contain the x86 reset vector.  POST later
moves the VGA image that started at `E0000h` into shadow memory at `C0000h`.

## DDR addresses

The ao486 cache drives MiSTer's 64-bit-word DDR address interface with the
upper nibble fixed to `3`.  Therefore:

| MiSTer byte address | Content |
|---|---|
| `300C0000h-300FFFFFh` | complete 256 KiB PC110 flash |
| `32000000h-320FFFFFh` | 1 MiB PC110 font ROM |

The FC7 and FC6 configuration entries use those byte addresses.  Internally
the cache converts its CPU dword address to MiSTer's 64-bit-word address.
