/*
 * Volatile, read-only hardware probe for an ARS USB2PCMCIA-R.
 *
 * Copyright (C) 2026 Ahmad Byagowi
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * This firmware intentionally leaves every FX2 GPIO as an input. It exposes
 * only vendor request 0xb0, which returns a snapshot of FX2 registers and pin
 * levels. No GPIF transaction or PC Card read/write cycle is generated.
 */

#include <autovector.h>
#include <fx2macros.h>
#include <fx2regs.h>
#include <i2c.h>
#include <setupdat.h>

volatile __bit got_setup_data;

static void snapshot_registers(void)
{
	EP0BUF[0] = 1; /* Snapshot format version. */
	EP0BUF[1] = CPUCS;
	EP0BUF[2] = IFCONFIG;
	EP0BUF[3] = PORTACFG;
	EP0BUF[4] = PORTCCFG;
	EP0BUF[5] = PORTECFG;
	EP0BUF[6] = IOA;
	EP0BUF[7] = OEA;
	EP0BUF[8] = IOB;
	EP0BUF[9] = OEB;
	EP0BUF[10] = IOC;
	EP0BUF[11] = OEC;
	EP0BUF[12] = IOD;
	EP0BUF[13] = OED;
	EP0BUF[14] = IOE;
	EP0BUF[15] = OEE;
	EP0BUF[16] = EP2468STAT;
	EP0BUF[17] = PINFLAGSAB;
	EP0BUF[18] = PINFLAGSCD;
	EP0BUF[19] = GPIFIDLECS;
	EP0BCH = 0;
	EP0BCL = 20;
}

void main(void)
{
	/* Keep all externally visible processor ports high-impedance. */
	OEA = 0;
	OEB = 0;
	OEC = 0;
	OED = 0;
	OEE = 0;

	got_setup_data = FALSE;
	RENUMERATE_UNCOND();
	SETCPUFREQ(CLK_48M);

	USE_USB_INTS();
	ENABLE_SUDAV();
	ENABLE_HISPEED();
	ENABLE_USBRESET();
	EA = 1;

	while (TRUE) {
		if (got_setup_data) {
			handle_setupdata();
			got_setup_data = FALSE;
		}
	}
}

BOOL handle_vendorcommand(BYTE command)
{
	WORD length;
	BYTE prom_address;

	if (!(SETUP_TYPE & 0x80))
		return FALSE;
	if (command == 0xb0 && SETUP_LENGTH() >= 20) {
		snapshot_registers();
		return TRUE;
	}
	if (command != 0xb1)
		return FALSE;
	length = SETUP_LENGTH();
	if (!length || length > sizeof(EP0BUF))
		return FALSE;
	prom_address = EEPROM_TWO_BYTE ? 0x51 : 0x50;
	if (!eeprom_read(prom_address, SETUP_VALUE(), length, EP0BUF))
		return FALSE;
	EP0BCH = 0;
	EP0BCL = (BYTE)length;
	return TRUE;
}

BOOL handle_get_descriptor(void)
{
	return FALSE;
}

BOOL handle_get_interface(BYTE interface, BYTE *alt_interface)
{
	if (interface)
		return FALSE;
	*alt_interface = 0;
	return TRUE;
}

BOOL handle_set_interface(BYTE interface, BYTE alt_interface)
{
	return interface == 0 && alt_interface == 0;
}

BYTE handle_get_configuration(void)
{
	return 1;
}

BOOL handle_set_configuration(BYTE configuration)
{
	return configuration == 1;
}

void sudav_isr(void) __interrupt(SUDAV_ISR)
{
	got_setup_data = TRUE;
	CLEAR_SUDAV();
}

void usbreset_isr(void) __interrupt(USBRESET_ISR)
{
	handle_hispeed(FALSE);
	CLEAR_USBRESET();
}

void hispeed_isr(void) __interrupt(HISPEED_ISR)
{
	handle_hispeed(TRUE);
	CLEAR_HISPEED();
}
