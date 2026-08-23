/* Read-only diagnostic client for the documented ARS public API. */

#include <dlfcn.h>
#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int (*ars_init_fn)(void);
typedef void (*ars_exit_fn)(void);
typedef unsigned char (*ars_rd8_fn)(unsigned long address);
typedef unsigned char (*ars_in8_fn)(unsigned short port);

enum access_space {
	ACCESS_MEMORY,
	ACCESS_IO,
};

static void usage(const char *name)
{
	fprintf(stderr,
		"usage: %s ADDRESS LENGTH\n"
		"       %s mem ADDRESS LENGTH\n"
		"       %s io PORT LENGTH\n",
		name, name, name);
}

int main(int argc, char **argv)
{
	ars_init_fn ars_init;
	ars_exit_fn ars_exit;
	ars_rd8_fn ars_rd8;
	ars_in8_fn ars_in8;
	enum access_space space = ACCESS_MEMORY;
	unsigned long address;
	unsigned long length;
	int arg_base = 1;
	char *end;
	void *library;

	if (argc == 4) {
		if (!strcmp(argv[1], "mem"))
			space = ACCESS_MEMORY;
		else if (!strcmp(argv[1], "io"))
			space = ACCESS_IO;
		else {
			usage(argv[0]);
			return 2;
		}
		arg_base = 2;
	} else if (argc != 3) {
		usage(argv[0]);
		return 2;
	}
	errno = 0;
	address = strtoul(argv[arg_base], &end, 0);
	if (errno || *end ||
		(space == ACCESS_MEMORY &&
		 (address < 0x000a0000UL || address > 0x000fffffUL)) ||
		(space == ACCESS_IO && address > 0xffffUL)) {
		usage(argv[0]);
		return 2;
	}
	errno = 0;
	length = strtoul(argv[arg_base + 1], &end, 0);
	if (errno || *end || !length ||
		(space == ACCESS_MEMORY &&
		 (length > 4096 || address + length - 1 > 0x000fffffUL)) ||
		(space == ACCESS_IO &&
		 (length > 256 || address + length - 1 > 0xffffUL))) {
		usage(argv[0]);
		return 2;
	}

	library = dlopen("./libarsusb4.so", RTLD_NOW | RTLD_LOCAL);
	if (!library) {
		fprintf(stderr, "libarsusb4.so: %s\n", dlerror());
		return 1;
	}
	ars_init = (ars_init_fn)dlsym(library, "ArsInit");
	ars_exit = (ars_exit_fn)dlsym(library, "ArsExit");
	ars_rd8 = (ars_rd8_fn)dlsym(library, "rd8");
	ars_in8 = (ars_in8_fn)dlsym(library, "in8");
	if (!ars_init || !ars_exit ||
		(space == ACCESS_MEMORY && !ars_rd8) ||
		(space == ACCESS_IO && !ars_in8)) {
		fprintf(stderr, "libarsusb4.so: required documented symbol missing\n");
		dlclose(library);
		return 1;
	}
	if (!ars_init()) {
		fprintf(stderr, "ARS enumerator is not available\n");
		dlclose(library);
		return 1;
	}

	for (unsigned long offset = 0; offset < length; ++offset) {
		if (!(offset & 15))
			printf(space == ACCESS_MEMORY ? "%08" PRIx32 ":" : "%04" PRIx32 ":",
				(uint32_t)(address + offset));
		printf(" %02x", space == ACCESS_MEMORY ?
			ars_rd8(address + offset) : ars_in8(address + offset));
		if ((offset & 15) == 15 || offset + 1 == length)
			putchar('\n');
	}

	ars_exit();
	dlclose(library);
	return 0;
}
