/*
 * One-shot diagnostic wrapper for the ARS ARM text enumerator.
 *
 * Some USB2PCMCIA-R/Card combinations assert card detect but return an open
 * attribute-memory bus during the enumerator's initial CIS scan.  This helper
 * starts the vendor enumerator under ptrace and, only when its Parse2() input
 * is a uniform open-bus value, substitutes the known Panasonic CF-JVR101 CIS.
 * The vendor program still performs all resource allocation and hardware
 * configuration itself.  No vendor firmware or code is included here.
 *
 * This is deliberately version-locked to the unstripped ARM arsenum4 binary
 * whose Parse2 symbol is 0x00015a78 and whose first instruction is e92d4800.
 */

#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ptrace.h>
#include <sys/types.h>
#include <sys/user.h>
#include <sys/wait.h>
#include <unistd.h>

#define PARSE2_ADDR 0x00015a78UL
#define PARSE2_PROLOGUE 0xe92d4800UL
#define ARM_BKPT 0xe7f001f0UL
#define CIS_SCAN_SIZE 512U

static const uint8_t cf_jvr101_cis[] = {
	0x15, 0x17, 0x04, 0x01,
	'P', 'A', 'N', 'A', 'S', 'O', 'N', 'I', 'C', 0x00,
	'C', 'F', '-', 'J', 'V', 'R', '1', '0', '1', 0x00, 0xff,
	0x21, 0x02, 0x02, 0x00,
	0x1a, 0x05, 0x01, 0x20, 0x00, 0x02, 0x03,
	0x1b, 0x0d, 0xe0, 0x41, 0x99, 0x27, 0x55, 0x4d,
	0x5d, 0x06, 0x63, 0x30, 0xff, 0xff, 0x08,
	0xff
};

static int read_bytes(pid_t pid, uintptr_t address, uint8_t *data, size_t len)
{
	size_t offset;

	for (offset = 0; offset < len; offset += sizeof(long)) {
		long word;
		size_t chunk = len - offset;

		errno = 0;
		word = ptrace(PTRACE_PEEKDATA, pid, (void *)(address + offset), NULL);
		if (word == -1 && errno != 0)
			return -1;
		if (chunk > sizeof(word))
			chunk = sizeof(word);
		memcpy(data + offset, &word, chunk);
	}
	return 0;
}

static int write_bytes(pid_t pid, uintptr_t address, const uint8_t *data,
		       size_t len)
{
	size_t offset;

	for (offset = 0; offset < len; offset += sizeof(long)) {
		long word = 0;
		size_t chunk = len - offset;

		if (chunk > sizeof(word))
			chunk = sizeof(word);
		if (chunk != sizeof(word)) {
			errno = 0;
			word = ptrace(PTRACE_PEEKDATA, pid,
				      (void *)(address + offset), NULL);
			if (word == -1 && errno != 0)
				return -1;
		}
		memcpy(&word, data + offset, chunk);
		if (ptrace(PTRACE_POKEDATA, pid, (void *)(address + offset),
			   (void *)word) == -1)
			return -1;
	}
	return 0;
}

static int uniform_open_bus(const uint8_t *data, size_t len)
{
	size_t i;

	if (data[0] != 0xff && data[0] != 0xf7 && data[0] != 0x00)
		return 0;
	for (i = 1; i < len; ++i) {
		if (data[i] != data[0])
			return 0;
	}
	return 1;
}

static int dump_scan(const char *path, const uint8_t *data, size_t len)
{
	FILE *file;

	if (!path || !*path)
		return 0;
	file = fopen(path, "wb");
	if (!file) {
		fprintf(stderr, "%s: %s\n", path, strerror(errno));
		return -1;
	}
	if (fwrite(data, 1, len, file) != len) {
		fprintf(stderr, "%s: %s\n", path, strerror(errno));
		fclose(file);
		return -1;
	}
	if (fclose(file)) {
		fprintf(stderr, "%s: %s\n", path, strerror(errno));
		return -1;
	}
	fprintf(stderr, "saved %zu-byte CIS parser input to %s\n", len, path);
	return 0;
}

int main(int argc, char **argv)
{
	uint8_t scan[CIS_SCAN_SIZE];
	struct user_regs regs;
	const char *dump_path = getenv("PC110_CIS_DUMP");
	const char *inject_env = getenv("PC110_CIS_INJECT");
	int inject_open_bus = !inject_env || strcmp(inject_env, "0");
	long original;
	uint8_t open_bus_value;
	pid_t child;
	int status;

	if (argc < 2) {
		fprintf(stderr, "usage: %s ARSENUM4 [ARG ...]\n", argv[0]);
		return 2;
	}

	child = fork();
	if (child == -1) {
		perror("fork");
		return 1;
	}
	if (child == 0) {
		if (ptrace(PTRACE_TRACEME, 0, NULL, NULL) == -1) {
			perror("PTRACE_TRACEME");
			_exit(126);
		}
		execv(argv[1], &argv[1]);
		perror("execv");
		_exit(127);
	}

	if (waitpid(child, &status, 0) == -1 || !WIFSTOPPED(status)) {
		fprintf(stderr, "enumerator did not stop after exec\n");
		return 1;
	}

	errno = 0;
	original = ptrace(PTRACE_PEEKTEXT, child, (void *)PARSE2_ADDR, NULL);
	if ((original == -1 && errno != 0) ||
	    ((uint32_t)original != PARSE2_PROLOGUE &&
	     (uint32_t)original != ARM_BKPT)) {
		fprintf(stderr,
			"unsupported arsenum4: Parse2 instruction is %08lx\n",
			(unsigned long)(uint32_t)original);
		ptrace(PTRACE_KILL, child, NULL, NULL);
		return 1;
	}
	if ((uint32_t)original == ARM_BKPT)
		original = PARSE2_PROLOGUE;
	if (ptrace(PTRACE_POKETEXT, child, (void *)PARSE2_ADDR,
		   (void *)ARM_BKPT) == -1 ||
	    ptrace(PTRACE_CONT, child, NULL, NULL) == -1) {
		perror("install/continue breakpoint");
		ptrace(PTRACE_KILL, child, NULL, NULL);
		return 1;
	}

	for (;;) {
		if (waitpid(child, &status, 0) == -1) {
			perror("waitpid");
			return 1;
		}
		if (WIFEXITED(status) || WIFSIGNALED(status)) {
			fprintf(stderr, "enumerator exited before CIS parsing\n");
			return 1;
		}
		if (!WIFSTOPPED(status))
			continue;
		if (ptrace(PTRACE_GETREGS, child, NULL, &regs) == -1) {
			perror("PTRACE_GETREGS");
			return 1;
		}
		if (regs.uregs[15] == PARSE2_ADDR ||
		    regs.uregs[15] == PARSE2_ADDR + 4) {
			regs.uregs[15] = PARSE2_ADDR;
			break;
		}
		if (ptrace(PTRACE_CONT, child, NULL,
			   (void *)(uintptr_t)WSTOPSIG(status)) == -1) {
			perror("PTRACE_CONT");
			return 1;
		}
	}

	if (read_bytes(child, regs.uregs[0], scan, sizeof(scan)) == -1) {
		perror("read Parse2 input");
		return 1;
	}
	if (dump_scan(dump_path, scan, sizeof(scan)) == -1)
		return 1;
	if (!uniform_open_bus(scan, sizeof(scan))) {
		fprintf(stderr,
			"real CIS data detected (starts %02x %02x); not replacing it\n",
			scan[0], scan[1]);
	} else if (!inject_open_bus) {
		fprintf(stderr,
			"uniform %02x attribute scan left unchanged because "
			"PC110_CIS_INJECT=0\n",
			scan[0]);
	} else {
		open_bus_value = scan[0];
		memset(scan, 0xff, sizeof(scan));
		memcpy(scan, cf_jvr101_cis, sizeof(cf_jvr101_cis));
		if (write_bytes(child, regs.uregs[0], scan, sizeof(scan)) == -1) {
			perror("write synthetic CIS");
			return 1;
		}
		fprintf(stderr,
			"replaced uniform %02x attribute scan with CF-JVR101 CIS\n",
			open_bus_value);
	}

	if (ptrace(PTRACE_POKETEXT, child, (void *)PARSE2_ADDR,
		   (void *)original) == -1 ||
	    ptrace(PTRACE_SETREGS, child, NULL, &regs) == -1 ||
	    ptrace(PTRACE_DETACH, child, NULL, NULL) == -1) {
		perror("restore/detach");
		return 1;
	}

	for (;;) {
		if (waitpid(child, &status, 0) == -1) {
			if (errno == EINTR)
				continue;
			perror("waitpid");
			return 1;
		}
		if (WIFEXITED(status))
			return WEXITSTATUS(status);
		if (WIFSIGNALED(status))
			return 128 + WTERMSIG(status);
	}
}
