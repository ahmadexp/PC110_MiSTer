/*
 * Minimal USB2PCMCIA-R runtime transport using Linux usbfs.
 *
 * This talks only to firmware that the user's licensed arsenum4 has already
 * loaded into volatile FX2 RAM.  It neither contains firmware nor writes the
 * adapter EEPROM.
 */

#include <errno.h>
#include <fcntl.h>
#include <linux/usbdevice_fs.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define FX2_CODE_SIZE 0x4000
#define FX2_CPUCS 0xe600

static void usage(const char *name)
{
	fprintf(stderr,
		"usage: %s DEVICE in8 PORT\n"
		"       %s DEVICE in16 PORT\n"
		"       %s DEVICE out8 PORT VALUE\n"
		"       %s DEVICE out16 PORT VALUE\n"
		"       %s DEVICE page MODE PAGE\n"
		"       %s DEVICE mem8 ADDRESS\n"
		"       %s DEVICE ram-load FIRMWARE.ihx\n"
		"       %s DEVICE raw-in REQUEST VALUE INDEX LENGTH\n"
		"       %s DEVICE raw-out REQUEST VALUE INDEX\n",
		name, name, name, name, name, name, name, name, name);
}

static int number(const char *text, uint32_t limit, uint32_t *value)
{
	char *end = NULL;
	unsigned long parsed;

	errno = 0;
	parsed = strtoul(text, &end, 0);
	if (errno || !end || *end || parsed > limit)
		return 0;
	*value = (uint32_t)parsed;
	return 1;
}

static int control(int fd, uint8_t type, uint8_t request, uint16_t value,
	uint16_t index, void *data, uint16_t length)
{
	struct usbdevfs_ctrltransfer transfer = {
		.bRequestType = type,
		.bRequest = request,
		.wValue = value,
		.wIndex = index,
		.wLength = length,
		.timeout = 1000,
		.data = data,
	};
	int result = ioctl(fd, USBDEVFS_CONTROL, &transfer);

	if (result < 0) {
		fprintf(stderr, "control %02x/%02x/%04x/%04x/%u: %s\n",
			type, request, value, index, length, strerror(errno));
		return -1;
	}
	if (result != length) {
		fprintf(stderr, "control %02x/%02x: short transfer %d/%u\n",
			type, request, result, length);
		return -1;
	}
	return 0;
}

static int hex_nibble(char ch)
{
	if (ch >= '0' && ch <= '9')
		return ch - '0';
	if (ch >= 'a' && ch <= 'f')
		return ch - 'a' + 10;
	if (ch >= 'A' && ch <= 'F')
		return ch - 'A' + 10;
	return -1;
}

static bool hex_byte(const char *text, uint8_t *value)
{
	int high = hex_nibble(text[0]);
	int low = hex_nibble(text[1]);

	if (high < 0 || low < 0)
		return false;
	*value = (uint8_t)((high << 4) | low);
	return true;
}

static int parse_ihx(const char *path, uint8_t *image, uint8_t *present)
{
	char line[600];
	uint32_t base = 0;
	unsigned line_number = 0;
	bool eof = false;
	FILE *file = fopen(path, "r");

	if (!file) {
		fprintf(stderr, "%s: %s\n", path, strerror(errno));
		return -1;
	}
	while (fgets(line, sizeof(line), file)) {
		uint8_t record[260];
		size_t length = strcspn(line, "\r\n");
		uint8_t count, type;
		uint16_t address;
		unsigned sum = 0;

		++line_number;
		if (!length)
			continue;
		if (line[0] != ':' || length < 11 || ((length - 1) & 1))
			goto malformed;
		for (size_t i = 0; i < (length - 1) / 2; ++i) {
			if (!hex_byte(&line[1 + i * 2], &record[i]))
				goto malformed;
		}
		count = record[0];
		if (length != (size_t)(count + 5) * 2 + 1)
			goto malformed;
		for (size_t i = 0; i < (size_t)count + 5; ++i)
			sum += record[i];
		if (sum & 0xff) {
			fprintf(stderr, "%s:%u: bad Intel HEX checksum\n", path,
				line_number);
			fclose(file);
			return -1;
		}
		address = (uint16_t)((record[1] << 8) | record[2]);
		type = record[3];
		if (type == 0) {
			uint32_t absolute = base + address;

			if (absolute + count > FX2_CODE_SIZE) {
				fprintf(stderr, "%s:%u: data outside FX2 code RAM\n",
					path, line_number);
				fclose(file);
				return -1;
			}
			memcpy(image + absolute, record + 4, count);
			memset(present + absolute, 1, count);
		} else if (type == 1) {
			if (count || address)
				goto malformed;
			eof = true;
			break;
		} else if (type == 2 || type == 4) {
			if (count != 2 || address)
				goto malformed;
			base = (uint32_t)((record[4] << 8) | record[5]) <<
				(type == 2 ? 4 : 16);
		} else if (type != 3 && type != 5) {
			fprintf(stderr, "%s:%u: unsupported Intel HEX record %02x\n",
				path, line_number, type);
			fclose(file);
			return -1;
		}
	}
	if (ferror(file)) {
		fprintf(stderr, "%s: %s\n", path, strerror(errno));
		fclose(file);
		return -1;
	}
	fclose(file);
	if (!eof) {
		fprintf(stderr, "%s: missing Intel HEX end record\n", path);
		return -1;
	}
	return 0;

malformed:
	fprintf(stderr, "%s:%u: malformed Intel HEX record\n", path,
		line_number);
	fclose(file);
	return -1;
}

static int ram_load(int fd, const char *path)
{
	uint8_t *image = calloc(FX2_CODE_SIZE, 1);
	uint8_t *present = calloc(FX2_CODE_SIZE, 1);
	uint8_t verify[4096];
	uint8_t cpucs = 1;
	size_t source_bytes = 0, span = 0;
	int result = -1;

	if (!image || !present) {
		perror("calloc");
		goto done;
	}
	if (parse_ihx(path, image, present))
		goto done;
	for (size_t offset = 0; offset < FX2_CODE_SIZE; ++offset) {
		if (present[offset]) {
			++source_bytes;
			span = offset + 1;
		}
	}
	if (!source_bytes) {
		fprintf(stderr, "%s: contains no FX2 code-RAM data\n", path);
		goto done;
	}
	span = (span + 1) & ~(size_t)1;
	if (control(fd, 0x40, 0xa0, FX2_CPUCS, 0, &cpucs, 1))
		goto done;
	for (size_t offset = 0; offset < span; offset += sizeof(verify)) {
		size_t length = span - offset;

		if (length > sizeof(verify))
			length = sizeof(verify);
		if (control(fd, 0x40, 0xa0, (uint16_t)offset, 0,
			image + offset, (uint16_t)length))
			goto release_cpu;
		if (control(fd, 0xc0, 0xa0, (uint16_t)offset, 0, verify,
			(uint16_t)length) || memcmp(verify, image + offset, length)) {
			fprintf(stderr, "FX2 code-RAM verify failed at %04zx\n", offset);
			goto release_cpu;
		}
	}
	fprintf(stderr, "verified %zu-byte volatile image (%zu source bytes)\n",
		span, source_bytes);
	result = 0;

release_cpu:
	cpucs = 0;
	if (control(fd, 0x40, 0xa0, FX2_CPUCS, 0, &cpucs, 1))
		result = -1;
done:
	free(present);
	free(image);
	return result;
}

int main(int argc, char **argv)
{
	uint32_t a = 0, b = 0, c = 0, d = 0;
	uint8_t data[512] = {0};
	int fd, result = 1;

	if (argc < 4) {
		usage(argv[0]);
		return 2;
	}
	fd = open(argv[1], O_RDWR);
	if (fd < 0) {
		fprintf(stderr, "%s: %s\n", argv[1], strerror(errno));
		return 1;
	}

	if (!strcmp(argv[2], "in8") && argc == 4 &&
	    number(argv[3], UINT16_MAX, &a)) {
		if (!control(fd, 0xc0, 5, 0, (uint16_t)a, data, 1)) {
			printf("%02x\n", data[0]);
			result = 0;
		}
	} else if (!strcmp(argv[2], "in16") && argc == 4 &&
		   number(argv[3], UINT16_MAX, &a)) {
		if (!control(fd, 0xc0, 4, 0, (uint16_t)a, data, 2)) {
			printf("%04x\n", (unsigned)data[0] | ((unsigned)data[1] << 8));
			result = 0;
		}
	} else if (!strcmp(argv[2], "out8") && argc == 5 &&
		   number(argv[3], UINT16_MAX, &a) &&
		   number(argv[4], UINT8_MAX, &b)) {
		result = control(fd, 0x40, 1, (uint16_t)b, (uint16_t)a,
			NULL, 0) ? 1 : 0;
	} else if (!strcmp(argv[2], "out16") && argc == 5 &&
		   number(argv[3], UINT16_MAX, &a) &&
		   number(argv[4], UINT16_MAX, &b)) {
		result = control(fd, 0x40, 0, (uint16_t)b, (uint16_t)a,
			NULL, 0) ? 1 : 0;
	} else if (!strcmp(argv[2], "page") && argc == 5 &&
		   number(argv[3], UINT16_MAX, &a) &&
		   number(argv[4], UINT16_MAX, &b)) {
		result = control(fd, 0x40, 9, (uint16_t)a, (uint16_t)b,
			NULL, 0) ? 1 : 0;
	} else if (!strcmp(argv[2], "mem8") && argc == 4 &&
		   number(argv[3], UINT32_MAX, &a)) {
		/* 0x0700 is the vendor runtime's PCMCIA attribute-memory mode. */
		if (!control(fd, 0x40, 9, 0x0700, (uint16_t)(a >> 16), NULL, 0) &&
		    !control(fd, 0xc0, 7, 0, (uint16_t)a, data, 1)) {
			printf("%02x\n", data[0]);
			result = 0;
		}
	} else if (!strcmp(argv[2], "ram-load") && argc == 4) {
		result = ram_load(fd, argv[3]) ? 1 : 0;
	} else if (!strcmp(argv[2], "raw-in") && argc == 7 &&
		   number(argv[3], UINT8_MAX, &a) &&
		   number(argv[4], UINT16_MAX, &b) &&
		   number(argv[5], UINT16_MAX, &c) &&
		   number(argv[6], sizeof(data), &d)) {
		if (!control(fd, 0xc0, (uint8_t)a, (uint16_t)b,
			(uint16_t)c, data, (uint16_t)d)) {
			for (uint32_t i = 0; i < d; ++i)
				printf("%02x%s", data[i], i + 1 == d ? "\n" : " ");
			result = 0;
		}
	} else if (!strcmp(argv[2], "raw-out") && argc == 6 &&
		   number(argv[3], UINT8_MAX, &a) &&
		   number(argv[4], UINT16_MAX, &b) &&
		   number(argv[5], UINT16_MAX, &c)) {
		result = control(fd, 0x40, (uint8_t)a, (uint16_t)b,
			(uint16_t)c, NULL, 0) ? 1 : 0;
	} else {
		usage(argv[0]);
		result = 2;
	}

	close(fd);
	return result;
}
