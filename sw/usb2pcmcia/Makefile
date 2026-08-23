CC ?= arm-linux-gnueabihf-gcc
CFLAGS ?= -O2 -Wall -Wextra -Werror
CPPFLAGS ?= $(shell pkg-config --cflags libusb-1.0)
LDLIBS ?= $(shell pkg-config --libs libusb-1.0)

.PHONY: all clean vendor-tools diagnostic-tools

all: usb2pcmcia-probe

vendor-tools: ars-readonly

diagnostic-tools: arsenum4-cis-inject usb2pcmcia-usbfs-reset \
	usb-hub-power-cycle arsenum4-usbfs-fwload usb2pcmcia-direct

usb2pcmcia-probe: usb2pcmcia_probe.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $< $(LDLIBS)

ars-readonly: ars_readonly.c
	$(CC) $(CFLAGS) -o $@ $< -ldl

arsenum4-cis-inject: arsenum4_cis_inject.c
	$(CC) $(CFLAGS) -static -o $@ $<

usb2pcmcia-usbfs-reset: usb2pcmcia_usbfs_reset.c
	$(CC) $(CFLAGS) -static -o $@ $<

usb-hub-power-cycle: usb_hub_power_cycle.c
	$(CC) $(CFLAGS) -static -o $@ $<

arsenum4-usbfs-fwload: arsenum4_usbfs_fwload.c
	$(CC) $(CFLAGS) -static -o $@ $<

usb2pcmcia-direct: usb2pcmcia_direct.c
	$(CC) $(CFLAGS) -static -o $@ $<

clean:
	rm -f usb2pcmcia-probe ars-readonly arsenum4-cis-inject \
		usb2pcmcia-usbfs-reset usb-hub-power-cycle \
		arsenum4-usbfs-fwload usb2pcmcia-direct
