ROOT := ../../..

.PHONY: all clean

all:
	iverilog -g2012 -Wall -o tb_rtc.vvp \
		tb_rtc.v \
		$(ROOT)/rtl/soc/rtc.v \
		$(ROOT)/rtl/common/simple_ram.v \
		$(ROOT)/rtl/pc110/pc110_ram_config.sv
	vvp tb_rtc.vvp

clean:
	rm -f tb_rtc.vvp
