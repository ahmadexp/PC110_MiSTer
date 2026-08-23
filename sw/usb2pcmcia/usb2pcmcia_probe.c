/*
 * Read-only USB characterization tool for the ARS USB2PCMCIA-R.
 *
 * The adapter enumerates as 071f:0048 and exposes only a vendor-specific
 * interface.  Non-empty OUT transfers are limited to Cypress's documented A0
 * loader request and the FX2LP's volatile 16 KiB code RAM; this utility never
 * writes the adapter EEPROM or supplies a command/payload to the PC Card bus.
 * The bulk probes issue the standard USB SET_INTERFACE request needed to
 * select an alternate setting. bulk-zlp sends only an empty USB packet for
 * endpoint discovery.
 */

#include <errno.h>
#include <inttypes.h>
#include <libusb.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ARS_VID 0x071f
#define ARS_PID 0x0048
#define USB_TIMEOUT_MS 500
#define FX2_CODE_SIZE 0x4000
#define FX2_CPUCS 0xe600

static void usage(const char *name)
{
	fprintf(stderr,
		"usage:\n"
		"  %s info\n"
		"  %s gpio-snapshot\n"
		"  %s control-in REQUEST VALUE INDEX LENGTH [OUTPUT]\n"
		"  %s ram-read ADDRESS LENGTH [OUTPUT]\n"
		"  %s ram-load FIRMWARE.ihx\n"
		"  %s bulk-in ALTSETTING ENDPOINT LENGTH [OUTPUT]\n"
		"  %s bulk-zlp ALTSETTING ENDPOINT\n"
		"  %s scan-control-in VALUE INDEX [LENGTH]\n"
		"  %s usb-reset\n"
		"\nNumbers accept decimal or 0x-prefixed hexadecimal. OUTPUT defaults "
		"to a hex dump; '-' also means hex dump.\n",
		name, name, name, name, name, name, name, name, name);
}

static bool parse_u32(const char *text, uint32_t max, uint32_t *value)
{
	char *end = NULL;
	unsigned long parsed;

	errno = 0;
	parsed = strtoul(text, &end, 0);
	if (errno || !end || *end || parsed > max)
		return false;
	*value = (uint32_t)parsed;
	return true;
}

static void dump_hex(const uint8_t *data, size_t length, uint32_t base)
{
	for (size_t offset = 0; offset < length; offset += 16) {
		printf("%08" PRIx32 ":", base + (uint32_t)offset);
		for (size_t i = 0; i < 16; ++i) {
			if (offset + i < length)
				printf(" %02x", data[offset + i]);
			else
				printf("   ");
		}
		printf("  |");
		for (size_t i = 0; i < 16 && offset + i < length; ++i) {
			uint8_t ch = data[offset + i];
			putchar(ch >= 32 && ch <= 126 ? ch : '.');
		}
		puts("|");
	}
}

static int emit_data(const char *output, const uint8_t *data, size_t length,
		uint32_t base)
{
	FILE *file;

	if (!output || !strcmp(output, "-")) {
		dump_hex(data, length, base);
		return 0;
	}

	file = fopen(output, "wb");
	if (!file) {
		fprintf(stderr, "%s: %s\n", output, strerror(errno));
		return -1;
	}
	if (fwrite(data, 1, length, file) != length) {
		fprintf(stderr, "%s: short write\n", output);
		fclose(file);
		return -1;
	}
	if (fclose(file)) {
		fprintf(stderr, "%s: %s\n", output, strerror(errno));
		return -1;
	}
	return 0;
}

static int print_info(libusb_device_handle *handle)
{
	libusb_device *device = libusb_get_device(handle);
	struct libusb_device_descriptor descriptor;
	struct libusb_config_descriptor *config = NULL;
	int status = libusb_get_device_descriptor(device, &descriptor);

	if (status < 0) {
		fprintf(stderr, "device descriptor: %s\n", libusb_error_name(status));
		return -1;
	}
	printf("%04x:%04x USB %x.%02x, configurations=%u\n",
		descriptor.idVendor, descriptor.idProduct,
		descriptor.bcdUSB >> 8, descriptor.bcdUSB & 0xff,
		descriptor.bNumConfigurations);

	status = libusb_get_active_config_descriptor(device, &config);
	if (status < 0) {
		fprintf(stderr, "configuration descriptor: %s\n",
			libusb_error_name(status));
		return -1;
	}
	for (uint8_t i = 0; i < config->bNumInterfaces; ++i) {
		const struct libusb_interface *interface = &config->interface[i];
		for (int a = 0; a < interface->num_altsetting; ++a) {
			const struct libusb_interface_descriptor *alt =
				&interface->altsetting[a];
			printf("interface=%u alt=%u endpoints=%u class=%02x/%02x/%02x\n",
				alt->bInterfaceNumber, alt->bAlternateSetting,
				alt->bNumEndpoints, alt->bInterfaceClass,
				alt->bInterfaceSubClass, alt->bInterfaceProtocol);
			for (uint8_t e = 0; e < alt->bNumEndpoints; ++e) {
				const struct libusb_endpoint_descriptor *ep =
					&alt->endpoint[e];
				printf("  endpoint=%02x attributes=%02x max_packet=%u interval=%u\n",
					ep->bEndpointAddress, ep->bmAttributes,
					ep->wMaxPacketSize, ep->bInterval);
			}
		}
	}
	libusb_free_config_descriptor(config);
	return 0;
}

static int control_in(libusb_device_handle *handle, uint8_t request,
		uint16_t value, uint16_t index, uint16_t length,
		const char *output, uint32_t base)
{
	uint8_t *buffer = calloc(length ? length : 1, 1);
	int status;

	if (!buffer) {
		perror("calloc");
		return -1;
	}
	status = libusb_control_transfer(handle,
		LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_VENDOR |
			LIBUSB_RECIPIENT_DEVICE,
		request, value, index, buffer, length, USB_TIMEOUT_MS);
	if (status < 0) {
		fprintf(stderr, "control IN %02x/%04x/%04x: %s\n",
			request, value, index, libusb_error_name(status));
		free(buffer);
		return -1;
	}
	printf("control IN %02x/%04x/%04x returned %d byte(s)\n",
		request, value, index, status);
	int result = emit_data(output, buffer, (size_t)status, base);
	free(buffer);
	return result;
}

static int gpio_snapshot(libusb_device_handle *handle)
{
	static const char *const labels[20] = {
		"format", "CPUCS", "IFCONFIG", "PORTACFG", "PORTCCFG",
		"PORTECFG", "IOA", "OEA", "IOB", "OEB", "IOC", "OEC",
		"IOD", "OED", "IOE", "OEE", "EP2468STAT", "PINFLAGSAB",
		"PINFLAGSCD", "GPIFIDLECS"
	};
	uint8_t buffer[20];
	int status = libusb_control_transfer(handle,
		LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_VENDOR |
			LIBUSB_RECIPIENT_DEVICE,
		0xb0, 0, 0, buffer, sizeof(buffer), USB_TIMEOUT_MS);

	if (status < 0) {
		fprintf(stderr, "GPIO snapshot: %s\n", libusb_error_name(status));
		return -1;
	}
	if (status != (int)sizeof(buffer) || buffer[0] != 1) {
		fprintf(stderr, "GPIO snapshot: unsupported response (%d byte(s))\n",
			status);
		return -1;
	}
	for (size_t i = 0; i < sizeof(buffer); ++i)
		printf("%-12s %02x\n", labels[i], buffer[i]);
	return 0;
}

static int ram_read(libusb_device_handle *handle, uint16_t address,
		uint32_t length, const char *output)
{
	const uint32_t max_chunk = 4096;
	uint8_t *buffer = calloc(length ? length : 1, 1);
	uint32_t offset = 0;

	if (!buffer) {
		perror("calloc");
		return -1;
	}
	while (offset < length) {
		uint16_t chunk = (uint16_t)((length - offset) > max_chunk ?
			max_chunk : length - offset);
		int status = libusb_control_transfer(handle,
			LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_VENDOR |
				LIBUSB_RECIPIENT_DEVICE,
			0xa0, (uint16_t)(address + offset), 0,
			buffer + offset, chunk, USB_TIMEOUT_MS);
		if (status < 0) {
			fprintf(stderr, "FX2-style A0 IN at %04x: %s\n",
				(uint16_t)(address + offset), libusb_error_name(status));
			free(buffer);
			return -1;
		}
		if (status != chunk) {
			fprintf(stderr, "FX2-style A0 IN at %04x: short read (%d/%u)\n",
				(uint16_t)(address + offset), status, chunk);
			free(buffer);
			return -1;
		}
		offset += chunk;
	}
	printf("A0 IN %04x..%04x returned %" PRIu32 " byte(s)\n",
		address, (uint16_t)(address + length - 1), length);
	int result = emit_data(output, buffer, length, address);
	free(buffer);
	return result;
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
		size_t length;
		uint8_t count;
		uint8_t type;
		uint16_t address;
		unsigned sum = 0;

		++line_number;
		length = strcspn(line, "\r\n");
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
		if (type == 0x00) {
			uint32_t absolute = base + address;

			if (absolute + count > FX2_CODE_SIZE) {
				fprintf(stderr,
					"%s:%u: data lies outside volatile FX2 code RAM\n",
					path, line_number);
				fclose(file);
				return -1;
			}
			memcpy(image + absolute, record + 4, count);
			memset(present + absolute, 1, count);
		} else if (type == 0x01) {
			if (count || address)
				goto malformed;
			eof = true;
			break;
		} else if (type == 0x02) {
			if (count != 2 || address)
				goto malformed;
			base = (uint32_t)((record[4] << 8) | record[5]) << 4;
		} else if (type == 0x04) {
			if (count != 2 || address)
				goto malformed;
			base = (uint32_t)((record[4] << 8) | record[5]) << 16;
		} else if (type != 0x03 && type != 0x05) {
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
	fprintf(stderr, "%s:%u: malformed Intel HEX record\n", path, line_number);
	fclose(file);
	return -1;
}

static int a0_write(libusb_device_handle *handle, uint16_t address,
		const uint8_t *data, uint16_t length)
{
	int status = libusb_control_transfer(handle,
		LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_VENDOR |
			LIBUSB_RECIPIENT_DEVICE,
		0xa0, address, 0, (uint8_t *)data, length, USB_TIMEOUT_MS);

	if (status < 0) {
		fprintf(stderr, "A0 OUT at %04x: %s\n", address,
			libusb_error_name(status));
		return -1;
	}
	if (status != length) {
		fprintf(stderr, "A0 OUT at %04x: short write (%d/%u)\n", address,
			status, length);
		return -1;
	}
	return 0;
}

static int ram_load(libusb_device_handle *handle, const char *path)
{
	uint8_t *image = calloc(FX2_CODE_SIZE, 1);
	uint8_t *present = calloc(FX2_CODE_SIZE, 1);
	uint8_t verify[4096];
	uint8_t cpucs = 1;
	size_t source_bytes = 0;
	size_t span = 0;
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
	/* This adapter's A0 implementation rounds odd addresses down. */
	span = (span + 1) & ~(size_t)1;
	if (a0_write(handle, FX2_CPUCS, &cpucs, 1))
		goto done;
	for (size_t offset = 0; offset < span; offset += sizeof(verify)) {
		size_t length = span - offset;
		int status;

		if (length > sizeof(verify))
			length = sizeof(verify);
		if (a0_write(handle, (uint16_t)offset, image + offset,
			(uint16_t)length))
			goto release_cpu;
		status = libusb_control_transfer(handle,
			LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_VENDOR |
				LIBUSB_RECIPIENT_DEVICE,
			0xa0, (uint16_t)offset, 0, verify, (uint16_t)length,
			USB_TIMEOUT_MS);
		if (status != (int)length || memcmp(verify, image + offset, length)) {
			fprintf(stderr, "FX2 code-RAM verify failed at %04zx\n", offset);
			goto release_cpu;
		}
	}
	printf("verified %zu-byte volatile FX2 code-RAM image "
		"(%zu source byte(s))\n", span, source_bytes);
	result = 0;

release_cpu:
	cpucs = 0;
	if (a0_write(handle, FX2_CPUCS, &cpucs, 1))
		result = -1;
	else if (!result)
		puts("FX2 CPU started; the USB device may re-enumerate");
done:
	free(present);
	free(image);
	return result;
}

static int bulk_in(libusb_device_handle *handle, int altsetting,
		uint8_t endpoint, int length, const char *output)
{
	uint8_t *buffer = calloc((size_t)length, 1);
	int transferred = 0;
	int status;

	if (!buffer) {
		perror("calloc");
		return -1;
	}
	status = libusb_claim_interface(handle, 0);
	if (status < 0) {
		fprintf(stderr, "claim interface: %s\n", libusb_error_name(status));
		free(buffer);
		return -1;
	}
	status = libusb_set_interface_alt_setting(handle, 0, altsetting);
	if (status < 0) {
		fprintf(stderr, "set altsetting %d: %s\n", altsetting,
			libusb_error_name(status));
		libusb_release_interface(handle, 0);
		free(buffer);
		return -1;
	}
	status = libusb_bulk_transfer(handle, endpoint, buffer, length,
		&transferred, USB_TIMEOUT_MS);
	if (status < 0 && status != LIBUSB_ERROR_TIMEOUT) {
		fprintf(stderr, "bulk IN %02x: %s\n", endpoint,
			libusb_error_name(status));
		libusb_release_interface(handle, 0);
		free(buffer);
		return -1;
	}
	printf("bulk IN %02x returned %d byte(s)%s\n", endpoint, transferred,
		status == LIBUSB_ERROR_TIMEOUT ? " before timeout" : "");
	int result = emit_data(output, buffer, (size_t)transferred, 0);
	libusb_release_interface(handle, 0);
	free(buffer);
	return result;
}

static int bulk_zlp(libusb_device_handle *handle, int altsetting,
		uint8_t endpoint)
{
	int transferred = 0;
	int status;

	status = libusb_claim_interface(handle, 0);
	if (status < 0) {
		fprintf(stderr, "claim interface: %s\n", libusb_error_name(status));
		return -1;
	}
	status = libusb_set_interface_alt_setting(handle, 0, altsetting);
	if (status < 0) {
		fprintf(stderr, "set altsetting %d: %s\n", altsetting,
			libusb_error_name(status));
		libusb_release_interface(handle, 0);
		return -1;
	}
	status = libusb_bulk_transfer(handle, endpoint, NULL, 0, &transferred,
		USB_TIMEOUT_MS);
	if (status < 0) {
		fprintf(stderr, "bulk ZLP %02x: %s\n", endpoint,
			libusb_error_name(status));
		libusb_release_interface(handle, 0);
		return -1;
	}
	printf("bulk ZLP %02x completed (%d byte(s))\n", endpoint, transferred);
	libusb_release_interface(handle, 0);
	return transferred ? -1 : 0;
}

static int scan_control_in(libusb_device_handle *handle, uint16_t value,
		uint16_t index, uint16_t length)
{
	uint8_t buffer[64];
	int matches = 0;

	if (length > sizeof(buffer))
		return -1;
	for (unsigned request = 0; request <= UINT8_MAX; ++request) {
		memset(buffer, 0, sizeof(buffer));
		int status = libusb_control_transfer(handle,
			LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_VENDOR |
				LIBUSB_RECIPIENT_DEVICE,
			(uint8_t)request, value, index, buffer, length, 25);
		if (status >= 0) {
			printf("request=%02x status=%d data=", request, status);
			for (int i = 0; i < status; ++i)
				printf("%02x", buffer[i]);
			putchar('\n');
			++matches;
		} else if (status != LIBUSB_ERROR_TIMEOUT &&
			   status != LIBUSB_ERROR_PIPE) {
			printf("request=%02x error=%s\n", request,
				libusb_error_name(status));
		}
	}
	printf("%d request(s) returned data or a zero-length success\n", matches);
	return 0;
}

int main(int argc, char **argv)
{
	libusb_context *context = NULL;
	libusb_device_handle *handle = NULL;
	uint32_t arg[4] = {0};
	int result = 1;
	int status;

	if (argc < 2) {
		usage(argv[0]);
		return 2;
	}
	status = libusb_init(&context);
	if (status < 0) {
		fprintf(stderr, "libusb_init: %s\n", libusb_error_name(status));
		return 1;
	}
	handle = libusb_open_device_with_vid_pid(context, ARS_VID, ARS_PID);
	if (!handle) {
		fprintf(stderr, "USB2PCMCIA-R %04x:%04x not found\n", ARS_VID, ARS_PID);
		goto done;
	}

	if (!strcmp(argv[1], "info") && argc == 2) {
		result = print_info(handle) ? 1 : 0;
	} else if (!strcmp(argv[1], "gpio-snapshot") && argc == 2) {
		result = gpio_snapshot(handle) ? 1 : 0;
	} else if (!strcmp(argv[1], "control-in") && (argc == 6 || argc == 7)) {
		if (!parse_u32(argv[2], UINT8_MAX, &arg[0]) ||
		    !parse_u32(argv[3], UINT16_MAX, &arg[1]) ||
		    !parse_u32(argv[4], UINT16_MAX, &arg[2]) ||
		    !parse_u32(argv[5], UINT16_MAX, &arg[3])) {
			usage(argv[0]);
			result = 2;
		} else {
			result = control_in(handle, (uint8_t)arg[0], (uint16_t)arg[1],
				(uint16_t)arg[2], (uint16_t)arg[3],
				argc == 7 ? argv[6] : NULL, arg[1]) ? 1 : 0;
		}
	} else if ((!strcmp(argv[1], "ram-read") ||
		    !strcmp(argv[1], "fx2-read")) && (argc == 4 || argc == 5)) {
		if (!parse_u32(argv[2], UINT16_MAX, &arg[0]) ||
		    !parse_u32(argv[3], 0x10000, &arg[1]) ||
		    !arg[1] ||
		    arg[0] + arg[1] > 0x10000) {
			usage(argv[0]);
			result = 2;
		} else {
			result = ram_read(handle, (uint16_t)arg[0], arg[1],
				argc == 5 ? argv[4] : NULL) ? 1 : 0;
		}
	} else if (!strcmp(argv[1], "ram-load") && argc == 3) {
		result = ram_load(handle, argv[2]) ? 1 : 0;
	} else if (!strcmp(argv[1], "bulk-in") && (argc == 5 || argc == 6)) {
		if (!parse_u32(argv[2], UINT8_MAX, &arg[0]) ||
		    !parse_u32(argv[3], UINT8_MAX, &arg[1]) ||
		    !(arg[1] & LIBUSB_ENDPOINT_IN) ||
		    !parse_u32(argv[4], INT32_MAX, &arg[2]) || !arg[2]) {
			usage(argv[0]);
			result = 2;
		} else {
			result = bulk_in(handle, (int)arg[0], (uint8_t)arg[1],
				(int)arg[2], argc == 6 ? argv[5] : NULL) ? 1 : 0;
		}
	} else if (!strcmp(argv[1], "bulk-zlp") && argc == 4) {
		if (!parse_u32(argv[2], UINT8_MAX, &arg[0]) ||
		    !parse_u32(argv[3], UINT8_MAX, &arg[1]) ||
		    (arg[1] & LIBUSB_ENDPOINT_IN)) {
			usage(argv[0]);
			result = 2;
		} else {
			result = bulk_zlp(handle, (int)arg[0], (uint8_t)arg[1]) ? 1 : 0;
		}
	} else if (!strcmp(argv[1], "scan-control-in") &&
		   (argc == 4 || argc == 5)) {
		if (!parse_u32(argv[2], UINT16_MAX, &arg[0]) ||
		    !parse_u32(argv[3], UINT16_MAX, &arg[1]) ||
		    (argc == 5 && !parse_u32(argv[4], 64, &arg[2]))) {
			usage(argv[0]);
			result = 2;
		} else {
			uint16_t length = argc == 5 ? (uint16_t)arg[2] : 2;
			result = scan_control_in(handle, (uint16_t)arg[0],
				(uint16_t)arg[1], length) ? 1 : 0;
		}
	} else if (!strcmp(argv[1], "usb-reset") && argc == 2) {
		status = libusb_reset_device(handle);
		if (status < 0) {
			fprintf(stderr, "USB reset: %s\n", libusb_error_name(status));
			result = 1;
		} else {
			puts("USB reset completed");
			result = 0;
		}
	} else {
		usage(argv[0]);
		result = 2;
	}

done:
	if (handle)
		libusb_close(handle);
	libusb_exit(context);
	return result;
}
