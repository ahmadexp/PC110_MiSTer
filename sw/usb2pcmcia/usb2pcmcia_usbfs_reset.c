/* Issue a targeted USB bus reset through Linux usbfs. */

#include <errno.h>
#include <fcntl.h>
#include <linux/usbdevice_fs.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	int fd;

	if (argc != 2) {
		fprintf(stderr, "usage: %s /dev/bus/usb/BBB/DDD\n", argv[0]);
		return 2;
	}
	fd = open(argv[1], O_WRONLY);
	if (fd == -1) {
		perror("open");
		return 1;
	}
	if (ioctl(fd, USBDEVFS_RESET, 0) == -1) {
		perror("USBDEVFS_RESET");
		close(fd);
		return 1;
	}
	close(fd);
	return 0;
}
