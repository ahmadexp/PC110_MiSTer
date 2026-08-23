/* Power-cycle one downstream port through the standard USB hub class API. */

#include <fcntl.h>
#include <linux/usb/ch11.h>
#include <linux/usb/ch9.h>
#include <linux/usbdevice_fs.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <unistd.h>

static int port_power(int fd, unsigned int port, int enabled)
{
	struct usbdevfs_ctrltransfer control = {
		.bRequestType = USB_DIR_OUT | USB_TYPE_CLASS | USB_RECIP_OTHER,
		.bRequest = enabled ? USB_REQ_SET_FEATURE : USB_REQ_CLEAR_FEATURE,
		.wValue = USB_PORT_FEAT_POWER,
		.wIndex = port,
		.wLength = 0,
		.timeout = 2000,
		.data = NULL,
	};

	return ioctl(fd, USBDEVFS_CONTROL, &control);
}

int main(int argc, char **argv)
{
	unsigned int port;
	unsigned int delay;
	int fd;

	if (argc < 3 || argc > 4) {
		fprintf(stderr, "usage: %s HUB_DEVICE PORT [OFF_SECONDS]\n",
			argv[0]);
		return 2;
	}
	port = (unsigned int)strtoul(argv[2], NULL, 0);
	delay = argc == 4 ? (unsigned int)strtoul(argv[3], NULL, 0) : 2U;
	if (port == 0 || delay == 0 || delay > 10) {
		fprintf(stderr, "invalid port or delay\n");
		return 2;
	}
	fd = open(argv[1], O_RDWR);
	if (fd == -1) {
		perror("open hub");
		return 1;
	}
	if (port_power(fd, port, 0) == -1) {
		perror("clear PORT_POWER");
		close(fd);
		return 1;
	}
	fprintf(stderr, "downstream power off\n");
	fflush(stderr);
	sleep(delay);
	if (port_power(fd, port, 1) == -1) {
		perror("set PORT_POWER");
		close(fd);
		return 1;
	}
	fprintf(stderr, "downstream power restored\n");
	close(fd);
	return 0;
}
