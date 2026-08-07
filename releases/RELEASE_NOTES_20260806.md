# IBM PC110 MiSTer-ready bundle, 2026-08-06

This is the first complete convenience package for installing the IBM PC110
core on a standard MiSTer system.

## Included

- Hardware-verified `PC110_20260729.rbf`, displayed as **IBM PC110**.
- PersonaWare English 2.0.6 VHD with the restored lower LCD captions,
  `EMM386 NOEMS` startup fix, modern picture support, and DOS Photo Manager.
- Image-owned 2-head, 32-sector, 128-cylinder CHS metadata.
- Backup-first on-MiSTer installer with payload checksum verification.
- ROM preparation tool, licenses, notices, and complete SHA-256 manifests.

## Firmware requirement

IBM BIOS and font ROM files are not included. Prepare dumps from hardware you
own and place the generated files in `/media/fat/games/ao486`. The installer
will configure existing `pc110_bios.bin` and optional `pc110_font.bin` files.

## Verification

The core completed IBM BIOS POST with error count `00` and first error code
`0000` on two DE10-Nano MiSTer systems. The bundled PersonaWare English image
is byte-for-byte identical to the verified 2.0.6 release asset.

Package SHA-256:

```text
dc7b1572aaa34b617675e8655f789e9fa2ca4929ca052fc579c229e7ca737a05  IBM-PC110-MiSTer-Ready-20260806.zip
```
