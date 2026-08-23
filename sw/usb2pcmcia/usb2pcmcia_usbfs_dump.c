/*
 * Read volatile Cypress FX2 RAM through Linux usbfs without libusb.
 *
 * This diagnostic intentionally implements only vendor control-IN request A0.
 * It cannot write adapter RAM, EEPROM, registers, or the attached PC Card.
 */

#include <errno.h>
#include <fcntl.h>
#include <linux/usbdevice_fs.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define MAX_FX2_RAM 0x4000U
#define MAX_CHUNK   4096U

static int parse_u32(const char *text, uint32_t max, uint32_t *value)
{
	char *end = NULL;
	unsigned long parsed;

	errno = 0;
	parsed = strtoul(text, &end, 0);
	if (errno || !end || *end || parsed > max)
		return 0;
	*value = (uint32_t)parsed;
	return 1;
}

int main(int argc, char **argv)
{
	uint32_t address, length;
	uint8_t *buffer;
	FILE *output;
	int device;

	if (argc != 5 ||
	    !parse_u32(argv[2], MAX_FX2_RAM - 1, &address) ||
	    !parse_u32(argv[3], MAX_FX2_RAM, &length) ||
	    !length || address + length > MAX_FX2_RAM) {
		fprintf(stderr, "usage: %s /dev/bus/usb/BBB/DDD ADDRESS LENGTH OUTPUT\n",
			argv[0]);
		return 2;
	}

	device = open(argv[1], O_RDWR);
	if (device < 0) {
		fprintf(stderr, "%s: %s\n", argv[1], strerror(errno));
		return 1;
	}
	buffer = malloc(length);
	if (!buffer) {
		perror("malloc");
		close(device);
		return 1;
	}

	for (uint32_t offset = 0; offset < length;) {
		uint32_t remaining = length - offset;
		uint16_t chunk = remaining > MAX_CHUNK ? MAX_CHUNK : (uint16_t)remaining;
		struct usbdevfs_ctrltransfer transfer = {
			.bRequestType = 0xC0,
			.bRequest = 0xA0,
			.wValue = (uint16_t)(address + offset),
			.wIndex = 0,
			.wLength = chunk,
			.timeout = 1000,
			.data = buffer + offset,
		};
		int result = ioctl(device, USBDEVFS_CONTROL, &transfer);
		if (result != chunk) {
			fprintf(stderr, "A0 IN at %04x: %s (%d/%u)\n",
				(unsigned)(address + offset),
				result < 0 ? strerror(errno) : "short read", result, chunk);
			free(buffer);
			close(device);
			return 1;
		}
		offset += chunk;
	}

	output = fopen(argv[4], "wb");
	if (!output || fwrite(buffer, 1, length, output) != length || fclose(output)) {
		fprintf(stderr, "%s: %s\n", argv[4], strerror(errno));
		free(buffer);
		close(device);
		return 1;
	}
	printf("read %u byte(s) from volatile FX2 RAM %04x..%04x\n",
		(unsigned)length, (unsigned)address, (unsigned)(address + length - 1));
	free(buffer);
	close(device);
	return 0;
}
