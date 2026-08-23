; USB descriptors for the volatile USB2PCMCIA-R safe probe.
;
; Copyright (C) 2026 Ahmad Byagowi
; SPDX-License-Identifier: GPL-3.0-or-later

.module DEV_DSCR

DSCR_DEVICE_TYPE=1
DSCR_CONFIG_TYPE=2
DSCR_STRING_TYPE=3
DSCR_INTERFACE_TYPE=4
DSCR_DEVQUAL_TYPE=6

    .globl _dev_dscr, _dev_qual_dscr, _highspd_dscr, _fullspd_dscr
    .globl _dev_strings, _dev_strings_end
    .area DSCR_AREA (CODE)

_dev_dscr:
    .db dev_dscr_end-_dev_dscr
    .db DSCR_DEVICE_TYPE
    .db 0x00, 0x02             ; USB 2.0
    .db 0xff, 0x00, 0x00       ; Vendor-specific device
    .db 64
    .db 0x1f, 0x07             ; VID 071f (from the adapter EEPROM)
    .db 0x48, 0x00             ; PID 0048
    .db 0x01, 0x00
    .db 1, 2, 0, 1
dev_dscr_end:

_dev_qual_dscr:
    .db dev_qual_dscr_end-_dev_qual_dscr
    .db DSCR_DEVQUAL_TYPE
    .db 0x00, 0x02
    .db 0xff, 0x00, 0x00
    .db 64, 1, 0
dev_qual_dscr_end:

_highspd_dscr:
    .db highspd_header_end-_highspd_dscr
    .db DSCR_CONFIG_TYPE
    .db highspd_end-_highspd_dscr, 0
    .db 1, 1, 0, 0x80, 0x32
highspd_header_end:
    .db 9, DSCR_INTERFACE_TYPE
    .db 0, 0, 0, 0xff, 0x00, 0x00, 0
highspd_end:

    .even
_fullspd_dscr:
    .db fullspd_header_end-_fullspd_dscr
    .db DSCR_CONFIG_TYPE
    .db fullspd_end-_fullspd_dscr, 0
    .db 1, 1, 0, 0x80, 0x32
fullspd_header_end:
    .db 9, DSCR_INTERFACE_TYPE
    .db 0, 0, 0, 0xff, 0x00, 0x00, 0
fullspd_end:

    .even
_dev_strings:
string0:
    .db string0_end-string0, DSCR_STRING_TYPE, 0x09, 0x04
string0_end:
string1:
    .db string1_end-string1, DSCR_STRING_TYPE
    .db 'P',0,'C',0,'1',0,'1',0,'0',0
string1_end:
string2:
    .db string2_end-string2, DSCR_STRING_TYPE
    .db 'S',0,'a',0,'f',0,'e',0,' ',0,'F',0,'X',0,'2',0,' ',0
    .db 'p',0,'i',0,'n',0,' ',0,'p',0,'r',0,'o',0,'b',0,'e',0
string2_end:
_dev_strings_end:
