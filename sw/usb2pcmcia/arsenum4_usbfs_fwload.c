/*
 * Load the USB2PCMCIA-R runtime directly from a user-supplied ARM arsenum4.
 *
 * The firmware bytes remain in the licensed vendor executable and are read at
 * runtime; this program contains no vendor firmware.  It supports only the
 * exact enumerator build validated below and writes only volatile FX2 RAM via
 * the Cypress 0xa0 loader request.  It has no EEPROM access.
 */

#include <errno.h>
#include <fcntl.h>
#include <linux/usbdevice_fs.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define FW_TABLE_OFFSET 0x000a8eec
#define FW_RECORD_SIZE 22
#define FW_RECORD_COUNT 277
#define PARSE2_OFFSET 0x00005a78
#define PARSE2_PROLOGUE 0xe92d4800U
#define FX2_CPUCS 0xe600
#define FX2_RAM_REQUEST 0xa0

struct fw_record {
	uint8_t length;
	uint8_t reserved;
	uint8_t address_lo;
	uint8_t address_hi;
	uint8_t type;
	uint8_t data[16];
	uint8_t padding;
};

static int read_exact(int fd, void *buffer, size_t length, off_t offset)
{
	ssize_t done = pread(fd, buffer, length, offset);

	if (done < 0)
		return -1;
	if ((size_t)done != length) {
		errno = EIO;
		return -1;
	}
	return 0;
}

static int fx2_transfer(int fd, int input, uint16_t address, void *data,
			uint16_t length)
{
	struct usbdevfs_ctrltransfer control = {
		.bRequestType = input ? 0xc0 : 0x40,
		.bRequest = FX2_RAM_REQUEST,
		.wValue = address,
		.wIndex = 0,
		.wLength = length,
		.timeout = 2000,
		.data = data,
	};
	int result = ioctl(fd, USBDEVFS_CONTROL, &control);

	if (result < 0)
		return -1;
	if (result != length) {
		errno = EIO;
		return -1;
	}
	return 0;
}

int main(int argc, char **argv)
{
	struct fw_record records[FW_RECORD_COUNT + 1];
	uint32_t prologue;
	uint8_t verify[17];
	uint8_t cpucs;
	unsigned int i;
	int firmware_fd;
	int usb_fd;

	if (argc != 3) {
		fprintf(stderr, "usage: %s USB_DEVICE ARM_ARSENUM4\n", argv[0]);
		return 2;
	}
	firmware_fd = open(argv[2], O_RDONLY);
	if (firmware_fd == -1) {
		perror("open arsenum4");
		return 1;
	}
	if (read_exact(firmware_fd, &prologue, sizeof(prologue), PARSE2_OFFSET) ||
	    prologue != PARSE2_PROLOGUE ||
	    read_exact(firmware_fd, records, sizeof(records), FW_TABLE_OFFSET)) {
		fprintf(stderr, "unsupported or truncated arsenum4 build\n");
		close(firmware_fd);
		return 1;
	}
	close(firmware_fd);

	if (records[0].length != 10 || records[0].type != 0 ||
	    records[0].address_lo != 0x92 || records[0].address_hi != 0x09 ||
	    records[FW_RECORD_COUNT].length != 0 ||
	    records[FW_RECORD_COUNT].type != 1) {
		fprintf(stderr, "arsenum4 firmware table signature mismatch\n");
		return 1;
	}

	usb_fd = open(argv[1], O_RDWR);
	if (usb_fd == -1) {
		perror("open USB device");
		return 1;
	}
	cpucs = 1;
	if (fx2_transfer(usb_fd, 0, FX2_CPUCS, &cpucs, 1)) {
		perror("stop FX2 CPU");
		close(usb_fd);
		return 1;
	}
	usleep(10000);

	for (i = 0; i < FW_RECORD_COUNT; ++i) {
		uint16_t address = (uint16_t)records[i].address_lo |
				   ((uint16_t)records[i].address_hi << 8);

		if (records[i].type != 0 || records[i].length > 16) {
			fprintf(stderr, "invalid firmware record %u; CPU left stopped\n",
				i);
			close(usb_fd);
			return 1;
		}
		if (fx2_transfer(usb_fd, 0, address, records[i].data,
				 records[i].length)) {
			perror("write FX2 RAM; CPU left stopped");
			close(usb_fd);
			return 1;
		}
	}

	for (i = 0; i < FW_RECORD_COUNT; ++i) {
		uint16_t address = (uint16_t)records[i].address_lo |
				   ((uint16_t)records[i].address_hi << 8);
		uint16_t read_address = address;
		uint16_t read_length = records[i].length;
		unsigned int data_offset = 0;

		/* This adapter's factory loader requires aligned verification reads. */
		if (read_address & 1U) {
			--read_address;
			++read_length;
			data_offset = 1;
		}
		if (fx2_transfer(usb_fd, 1, read_address, verify, read_length) ||
		    memcmp(verify + data_offset, records[i].data,
			   records[i].length) != 0) {
			fprintf(stderr,
				"verify failed at record %u; CPU left stopped\n", i);
			close(usb_fd);
			return 1;
		}
	}

	cpucs = 0;
	if (fx2_transfer(usb_fd, 0, FX2_CPUCS, &cpucs, 1)) {
		perror("start FX2 CPU");
		close(usb_fd);
		return 1;
	}
	close(usb_fd);
	fprintf(stderr, "loaded and verified %u volatile firmware records\n",
		FW_RECORD_COUNT);
	return 0;
}
