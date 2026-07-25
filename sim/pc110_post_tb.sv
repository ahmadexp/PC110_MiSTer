// PC110 early-POST hang reproduction.
//
// Bare ao486 CPU + iobus + pc110_chipset with the real 256 KiB flash image
// behaviorally mapped at C0000h-FFFFFh.  Unmapped I/O reads return FFh as in
// rtl/system.v.  CMOS, KBC status, and port 92h are stubbed to cold-boot
// values.  The testbench traces every device-side I/O access and every CPU
// memory transaction, then reports the tail of both traces so the hang loop
// and the last progress point are visible.
//
// Usage: scripts/sim-post.sh

`timescale 1ns/1ns

module pc110_post_tb();

integer CYCLES_MAX = 6_000_000;
initial if($value$plusargs("cycles=%d", CYCLES_MAX));
localparam TRACE_TAIL = 64;

reg clk = 0;
reg reset = 1;
always #5 clk = ~clk;

// ---------------------------------------------------------------- CPU

wire [29:0] avm_address;      // dword address
wire [31:0] avm_writedata;
wire  [3:0] avm_byteenable;
wire  [3:0] avm_burstcount;
wire        avm_write;
wire        avm_read;
wire        avm_readdatavalid;
wire [31:0] avm_readdata;

wire        cpu_io_read_do;
wire [15:0] cpu_io_read_address;
wire  [2:0] cpu_io_read_length;
wire [31:0] cpu_io_read_data;
wire        cpu_io_read_done;
wire        cpu_io_write_do;
wire [15:0] cpu_io_write_address;
wire  [2:0] cpu_io_write_length;
wire [31:0] cpu_io_write_data;
wire        cpu_io_write_done;
wire        a20_enable;

wire avm_waitrequest;

ao486 ao486
(
	.clk               (clk),
	.rst_n             (~reset),

	.cache_disable     (1'b0),

	.avm_address       (avm_address),
	.avm_writedata     (avm_writedata),
	.avm_byteenable    (avm_byteenable),
	.avm_burstcount    (avm_burstcount),
	.avm_write         (avm_write),
	.avm_read          (avm_read),
	.avm_waitrequest   (avm_waitrequest),
	.avm_readdatavalid (avm_readdatavalid),
	.avm_readdata      (avm_readdata),

	.interrupt_do      (1'b0),
	.interrupt_vector  (8'd0),
	.interrupt_done    (),

	.io_read_do        (cpu_io_read_do),
	.io_read_address   (cpu_io_read_address),
	.io_read_length    (cpu_io_read_length),
	.io_read_data      (cpu_io_read_data),
	.io_read_done      (cpu_io_read_done),
	.io_write_do       (cpu_io_write_do),
	.io_write_address  (cpu_io_write_address),
	.io_write_length   (cpu_io_write_length),
	.io_write_data     (cpu_io_write_data),
	.io_write_done     (cpu_io_write_done),

	.a20_enable        (a20_enable),

	.dma_address       (16'd0),
	.dma_16bit         (1'b0),
	.dma_read          (1'b0),
	.dma_readdata      (),
	.dma_readdatavalid (),
	.dma_waitrequest   (),
	.dma_write         (1'b0),
	.dma_writedata     (8'd0)
);

// ---------------------------------------------------------------- memory
// Real FPGA memory path: the modified l2_cache between the CPU and a
// behavioral 64-bit DDR model.  The BIOS image is preloaded at DDR byte
// offset C0000h exactly as MiSTer Main writes it (x86 base 30000000h maps
// to DDR model offset 0).

reg [7:0] mem [0:1048575];

integer mi;
initial begin
	for(mi = 0; mi < 1048576; mi = mi + 1) mem[mi] = 8'h00;
	$readmemh("artifacts/test/pc110_bios.hex", mem, 20'hC0000, 20'hFFFFF);
end

wire [24:0] DDRAM_ADDR;
wire [63:0] DDRAM_DIN;
reg  [63:0] DDRAM_DOUT;
reg         DDRAM_DOUT_READY = 0;
wire  [7:0] DDRAM_BE;
wire  [7:0] DDRAM_BURSTCNT;
wire        DDRAM_RD;
wire        DDRAM_WE;

// 64 MiB of qwords: covers the 1 MiB x86 space and the font window base
reg [63:0] ddr [0:8388607];

integer di;
initial begin
	for(di = 0; di < 20'hC0000/8; di = di + 1) ddr[di] = 64'd0;
	for(di = 20'hC0000/8; di < 21'h100000/8; di = di + 1)
		ddr[di] = {mem[di*8+7], mem[di*8+6], mem[di*8+5], mem[di*8+4],
		           mem[di*8+3], mem[di*8+2], mem[di*8+1], mem[di*8+0]};
end

// Latency and backpressure model: reads are answered after a variable
// delay (8-23 cycles to first beat) and DDRAM_BUSY asserts pseudo-randomly,
// approximating the HPS DDR3 port.  +ddrfast=1 restores the ideal model.
integer ddr_fast = 0;
initial if($value$plusargs("ddrfast=%d", ddr_fast));

reg [15:0] lfsr = 16'hACE1;
always @(posedge clk) lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};

reg        ddr_busy_r = 0;
always @(posedge clk) ddr_busy_r <= (ddr_fast == 0) && (lfsr[1:0] == 2'b11);
wire ddram_busy_w = ddr_busy_r;

reg [7:0]  ddr_burst_left = 0;
reg [24:0] ddr_burst_addr;
integer    ddr_lat = 0;
always @(posedge clk) begin
	if(DDRAM_RD && !ddram_busy_w && ddr_burst_left == 0 && ddr_lat == 0) begin
		ddr_burst_left <= DDRAM_BURSTCNT;
		ddr_burst_addr <= DDRAM_ADDR;
		ddr_lat        <= (ddr_fast != 0) ? 1 : (8 + {28'd0, lfsr[3:0]});
		DDRAM_DOUT_READY <= 1'b0;
	end
	else if(ddr_lat > 1) begin
		ddr_lat <= ddr_lat - 1;
		DDRAM_DOUT_READY <= 1'b0;
	end
	else if(ddr_lat == 1 && ddr_burst_left != 0) begin
		DDRAM_DOUT       <= ddr[ddr_burst_addr[22:0]];
		DDRAM_DOUT_READY <= 1'b1;
		ddr_burst_left   <= ddr_burst_left - 8'd1;
		ddr_burst_addr   <= ddr_burst_addr + 25'd1;
		if(ddr_burst_left == 8'd1) ddr_lat <= 0;
	end
	else DDRAM_DOUT_READY <= 1'b0;

	if(DDRAM_WE && !ddram_busy_w) begin
		if(DDRAM_BE[0]) ddr[DDRAM_ADDR[22:0]][7:0]   <= DDRAM_DIN[7:0];
		if(DDRAM_BE[1]) ddr[DDRAM_ADDR[22:0]][15:8]  <= DDRAM_DIN[15:8];
		if(DDRAM_BE[2]) ddr[DDRAM_ADDR[22:0]][23:16] <= DDRAM_DIN[23:16];
		if(DDRAM_BE[3]) ddr[DDRAM_ADDR[22:0]][31:24] <= DDRAM_DIN[31:24];
		if(DDRAM_BE[4]) ddr[DDRAM_ADDR[22:0]][39:32] <= DDRAM_DIN[39:32];
		if(DDRAM_BE[5]) ddr[DDRAM_ADDR[22:0]][47:40] <= DDRAM_DIN[47:40];
		if(DDRAM_BE[6]) ddr[DDRAM_ADDR[22:0]][55:48] <= DDRAM_DIN[55:48];
		if(DDRAM_BE[7]) ddr[DDRAM_ADDR[22:0]][63:56] <= DDRAM_DIN[63:56];
	end
end

wire [15:0] pc110_shadow_we_w;
wire  [6:0] pc110_font_bank_w;
wire  [7:0] pc110_font_seg_w;
wire        pc110_font_en_w;
wire  [7:0] pc110_dram_cfg0_w;
wire        postlog_tx_w;

l2_cache cache
(
	.CLK               (clk),
	.RESET             (reset),

	.DISABLE           (1'b0),

	.CPU_ADDR          (avm_address),
	.CPU_DIN           (avm_writedata),
	.CPU_DOUT          (avm_readdata),
	.CPU_DOUT_READY    (avm_readdatavalid),
	.CPU_BE            (avm_byteenable),
	.CPU_BURSTCNT      (avm_burstcount),
	.CPU_BUSY          (avm_waitrequest),
	.CPU_RD            (avm_read),
	.CPU_WE            (avm_write),

	.DDRAM_ADDR        (DDRAM_ADDR),
	.DDRAM_DIN         (DDRAM_DIN),
	.DDRAM_DOUT        (DDRAM_DOUT),
	.DDRAM_DOUT_READY  (DDRAM_DOUT_READY),
	.DDRAM_BE          (DDRAM_BE),
	.DDRAM_BURSTCNT    (DDRAM_BURSTCNT),
	.DDRAM_BUSY        (ddram_busy_w),
	.DDRAM_RD          (DDRAM_RD),
	.DDRAM_WE          (DDRAM_WE),

	.VGA_ADDR          (),
	.VGA_DIN           (8'h00),
	.VGA_DOUT          (),
	.VGA_RD            (),
	.VGA_WE            (),
	.VGA_MODE          (3'd0),

	.VGA_WR_SEG        (6'd0),
	.VGA_RD_SEG        (6'd0),
	.VGA_FB_EN         (1'b0),

	.PC110_SHADOW_WE   (pc110_shadow_we_w),
	.PC110_FONT_BANK   (pc110_font_bank_w),
	.PC110_FONT_SEG    (pc110_font_seg_w),
	.PC110_FONT_EN     (pc110_font_en_w),
	.PC110_DRAM_CFG0   (pc110_dram_cfg0_w)
);

// ---------------------------------------------------------------- iobus

wire [15:0] iobus_address;
wire        iobus_write;
wire        iobus_read;
wire  [2:0] iobus_datasize;
wire [31:0] iobus_writedata;
wire [31:0] iobus_readdata;

iobus iobus
(
	.clk               (clk),
	.reset             (reset),

	.cpu_read_do       (cpu_io_read_do),
	.cpu_read_address  (cpu_io_read_address),
	.cpu_read_length   (cpu_io_read_length),
	.cpu_read_data     (cpu_io_read_data),
	.cpu_read_done     (cpu_io_read_done),
	.cpu_write_do      (cpu_io_write_do),
	.cpu_write_address (cpu_io_write_address),
	.cpu_write_length  (cpu_io_write_length),
	.cpu_write_data    (cpu_io_write_data),
	.cpu_write_done    (cpu_io_write_done),

	.bus_address       (iobus_address),
	.bus_write         (iobus_write),
	.bus_read          (iobus_read),
	.bus_io32          (1'b0),
	.bus_datasize      (iobus_datasize),
	.bus_writedata     (iobus_writedata),
	.bus_readdata      (iobus_readdata),
	.bus_wait          (1'b0)
);

// ---------------------------------------------------------------- devices

wire  [7:0] pc110_readdata;
wire        pc110_cs;

pc110_chipset pc110
(
	.clk                 (clk),
	.reset               (reset),
	.io_address          (iobus_address),
	.io_read             (iobus_read),
	.io_write            (iobus_write),
	.io_writedata        (iobus_writedata[7:0]),
	.io_readdata         (pc110_readdata),
	.io_cs               (pc110_cs),
	.shadow_write_enable (pc110_shadow_we_w),
	.shadow_read_enable  (),
	.font_bank_select    (pc110_font_bank_w),
	.font_window_segment (pc110_font_seg_w),
	.font_window_enable  (pc110_font_en_w),
	.dram_cfg0           (pc110_dram_cfg0_w),
	.postlog_tx          (postlog_tx_w)
);



// real AT peripherals: PIT (40h-43h, 61h), 8042 KBC (60h-67h, 90h-9Fh),
// and the PC110-modified RTC (70h/71h) with Main's CMOS image injected
// over the mgmt port.
wire pit_cs = ({iobus_address[15:2],2'd0} == 16'h0040) || (iobus_address == 16'h0061);
wire ps2_io_cs  = ({iobus_address[15:3],3'd0} == 16'h0060);
wire ps2_ctl_cs = ({iobus_address[15:4],4'd0} == 16'h0090);
wire rtc_cs = ({iobus_address[15:1],1'b0} == 16'h0070);

wire [7:0] pit_readdata;
wire [7:0] ps2_readdata;
wire [7:0] rtc_readdata;

pit pit
(
	.clk          (clk),
	.rst_n        (~reset),
	.clock_rate   (28'd100000000),
	.io_address   ({iobus_address[5],iobus_address[1:0]}),
	.io_writedata (iobus_writedata[7:0]),
	.io_readdata  (pit_readdata),
	.io_read      (iobus_read & pit_cs),
	.io_write     (iobus_write & pit_cs),
	.speaker_out  (),
	.irq          ()
);

// Behavioral 8042 KBC: self-test AAh -> 55h, interface test ABh -> 00h,
// command-byte access, D1h output-port writes (A20), keyboard FFh reset
// -> FAh + AAh.  Matches what early PC110 POST depends on.
reg  [7:0] kbc_obuf [0:7];
integer    kbc_head = 0, kbc_tail = 0;
wire       kbc_obf = (kbc_head != kbc_tail);
reg        kbc_sys = 0;
reg  [7:0] kbc_cmdbyte = 8'h00;
reg  [1:0] kbc_pending = 0;    // 1: next 60h write is cmdbyte, 2: output port
reg        kbc_last_cmd = 0;
reg  [7:0] kbc_outport = 8'h02;
reg  [7:0] port92 = 8'h02;

task kbc_push(input [7:0] b);
	begin
		kbc_obuf[kbc_tail] = b;
		kbc_tail = (kbc_tail + 1) % 8;
	end
endtask

assign a20_enable = port92[1] | kbc_outport[1];

wire [7:0] kbc_status = {2'b00, 1'b0, 1'b1, kbc_last_cmd, kbc_sys, 1'b0, kbc_obf};
assign ps2_readdata =
	(iobus_address == 16'h0064) ? kbc_status :
	(iobus_address == 16'h0060) ? kbc_obuf[kbc_head] :
	(iobus_address == 16'h0092) ? port92 :
	                              8'hFF;

always @(posedge clk) begin
	if(iobus_read && iobus_address == 16'h0060 && kbc_obf)
		kbc_head <= (kbc_head + 1) % 8;

	if(iobus_write && iobus_address == 16'h0064) begin
		kbc_last_cmd <= 1'b1;
		case(iobus_writedata[7:0])
			8'hAA: begin kbc_push(8'h55); kbc_sys <= 1'b1; end
			8'hAB: kbc_push(8'h00);
			8'h20: kbc_push(kbc_cmdbyte);
			8'h60: kbc_pending <= 2'd1;
			8'hD1: kbc_pending <= 2'd2;
			default: ;
		endcase
	end
	if(iobus_write && iobus_address == 16'h0060) begin
		kbc_last_cmd <= 1'b0;
		case(kbc_pending)
			2'd1: begin kbc_cmdbyte <= iobus_writedata[7:0]; kbc_pending <= 0; if(iobus_writedata[2]) kbc_sys <= 1'b1; end
			2'd2: begin kbc_outport <= iobus_writedata[7:0]; kbc_pending <= 0; end
			default: begin
				// keyboard device command
				kbc_push(8'hFA);
				if(iobus_writedata[7:0] == 8'hFF) kbc_push(8'hAA);
			end
		endcase
	end
	if(iobus_write && iobus_address == 16'h0092) port92 <= iobus_writedata[7:0];
end

// Behavioral RTC/CMOS: index/data ports with Main's CMOS image, UIP bit
// toggling in register 0Ah, static clean status.
reg [7:0] cmos_ram [0:127];
reg [6:0] cmos_idx = 0;
integer ci;
initial begin
	for(ci = 0; ci < 128; ci = ci + 1) cmos_ram[ci] = 8'h00;
	cmos_ram[8'h0A] = 8'h26; cmos_ram[8'h0B] = 8'h02;
	cmos_ram[8'h0D] = 8'h80;
	cmos_ram[8'h10] = 8'h40;                        // one 1.44M floppy
	cmos_ram[8'h14] = 8'h4D;                        // equipment
	cmos_ram[8'h15] = 8'h80; cmos_ram[8'h16] = 8'h02;   // 640K base
	cmos_ram[8'h17] = 8'h00; cmos_ram[8'h18] = 8'h3C;   // ext mem (16M cfg)
	cmos_ram[8'h2E] = 8'h00; cmos_ram[8'h2F] = 8'hCD;   // checksum
end

reg [12:0] uip_div = 0;
wire uip = (uip_div < 13'd150);
always @(posedge clk) uip_div <= uip_div + 1'b1;

assign rtc_readdata =
	(iobus_address[0] == 1'b0) ? {1'b0, cmos_idx} :
	(cmos_idx == 7'h0A)        ? {uip, cmos_ram[8'h0A][6:0]} :
	                             cmos_ram[cmos_idx];

always @(posedge clk) begin
	if(iobus_write && rtc_cs && !iobus_address[0]) cmos_idx <= iobus_writedata[6:0];
	if(iobus_write && rtc_cs &&  iobus_address[0]) cmos_ram[cmos_idx] <= iobus_writedata[7:0];
end

wire [7:0] io_read8 =
	pc110_cs               ? pc110_readdata :
	pit_cs                 ? pit_readdata :
	(ps2_io_cs|ps2_ctl_cs) ? ps2_readdata :
	rtc_cs                 ? rtc_readdata :
	                         8'hFF;

assign iobus_readdata = {4{io_read8}};

// ---------------------------------------------------------------- tracing

integer cycles = 0;

// decode the POST-logger UART stream (100 MHz / 115200 = 868... the
// chipset divider is built for 90 MHz; at the TB clock the bit time is
// POSTLOG_DIV cycles regardless, so sample mid-bit by counting cycles)
reg  [3:0] plmon_bit = 0;
reg [11:0] plmon_div = 0;
reg  [7:0] plmon_sh = 0;
reg  [7:0] plmon_tag = 0;
reg        plmon_have_tag = 0;
always @(posedge clk) begin
	if(plmon_bit == 0) begin
		if(!postlog_tx_w) begin
			plmon_bit <= 9;
			plmon_div <= 12'd782 + 12'd391;
		end
	end
	else if(plmon_div != 0) plmon_div <= plmon_div - 1'b1;
	else begin
		if(plmon_bit != 1) plmon_sh <= {postlog_tx_w, plmon_sh[7:1]};
		else begin
			if(!plmon_have_tag) begin plmon_tag <= plmon_sh; plmon_have_tag <= 1; end
			else begin
				$display("PLOG %c %02x  (t=%0d)", plmon_tag, plmon_sh, cycles);
				plmon_have_tag <= 0;
			end
		end
		plmon_bit <= plmon_bit - 1'b1;
		plmon_div <= 12'd782;
	end
end
integer io_count = 0;
integer ram_write_count = 0;

reg [47:0] io_tail_addrop [0:TRACE_TAIL-1];   // {op(8), addr(16), data(8), pad}
reg [15:0] io_tail_addr [0:TRACE_TAIL-1];
reg  [7:0] io_tail_data [0:TRACE_TAIL-1];
reg        io_tail_iswr [0:TRACE_TAIL-1];
integer io_tail_pos = 0;

reg [31:0] rd_tail_addr [0:TRACE_TAIL-1];
integer rd_tail_pos = 0;
integer rd_count = 0;

// live EIP trace from the execute stage
reg [31:0] eip_tail [0:255];
integer eip_tail_pos = 0;
reg [31:0] last_exe_eip = 32'hFFFFFFFF;
reg [31:0] last_caller_eip = 32'hFFFFFFFF;
always @(posedge clk)
	if(ao486.pipeline_inst.exe_ready &&
	   !(ao486.pipeline_inst.exe_eip >= 32'h0000DB60 && ao486.pipeline_inst.exe_eip < 32'h0000DD00))
		last_caller_eip <= ao486.pipeline_inst.exe_eip;
always @(posedge clk) begin
	if(ao486.pipeline_inst.exe_ready && ao486.pipeline_inst.exe_eip !== last_exe_eip) begin
		last_exe_eip <= ao486.pipeline_inst.exe_eip;
		eip_tail[eip_tail_pos] <= ao486.pipeline_inst.exe_eip;
		eip_tail_pos <= (eip_tail_pos + 1) % 256;
		$display("XEIP %08x cf=%b", ao486.pipeline_inst.exe_eip, ao486.pipeline_inst.cflag);
	end
end

reg cflag_d = 0;
always @(posedge clk) begin
	cflag_d <= ao486.pipeline_inst.cflag;
	if(cflag_d !== ao486.pipeline_inst.cflag && !reset)
		$display("CFCHG cf=%b->%b exe_eip=%08x t=%0d", cflag_d, ao486.pipeline_inst.cflag, ao486.pipeline_inst.exe_eip, cycles);
	if(ao486.exception_inst.exc_load)
		$display("EXC vector=%02x eip=%08x exe_eip=%08x t=%0d", ao486.exception_inst.exc_vector, ao486.exception_inst.exc_eip, ao486.pipeline_inst.exe_eip, cycles);
end

reg iobus_read_d = 0;
always @(posedge clk) begin
	iobus_read_d <= iobus_read;

	if(iobus_write && (iobus_address == 16'h00EC || iobus_address == 16'h00ED))
		$display("ECED %s %02x  caller=%08x t=%0d", (iobus_address==16'h00EC)?"idx":"dat", iobus_writedata[7:0], last_caller_eip, cycles);
	if(iobus_write) begin
		io_tail_addr[io_tail_pos] <= iobus_address;
		io_tail_data[io_tail_pos] <= iobus_writedata[7:0];
		io_tail_iswr[io_tail_pos] <= 1'b1;
		io_tail_pos <= (io_tail_pos + 1) % TRACE_TAIL;
		io_count <= io_count + 1;
		if(io_count < 400) $display("IOW %04x <= %02x  (t=%0d)", iobus_address, iobus_writedata[7:0], cycles);
	end
	if(iobus_read_d && !iobus_read) begin
		io_tail_addr[io_tail_pos] <= iobus_address;
		io_tail_data[io_tail_pos] <= io_read8;
		io_tail_iswr[io_tail_pos] <= 1'b0;
		io_tail_pos <= (io_tail_pos + 1) % TRACE_TAIL;
		io_count <= io_count + 1;
		if(io_count < 400) $display("IOR %04x => %02x  (t=%0d)", iobus_address, io_read8, cycles);
	end

	if(avm_read && !avm_waitrequest) begin
		rd_tail_addr[rd_tail_pos] <= {avm_address,2'b00};
		rd_tail_pos <= (rd_tail_pos + 1) % TRACE_TAIL;
		rd_count <= rd_count + 1;
		if(rd_count < 40) $display("AVMRD  addr=%08x burst=%0d  (t=%0d)", {avm_address,2'b00}, avm_burstcount, cycles);
	end
	if(avm_readdatavalid && rd_count < 40) $display("AVMDAT %08x  (t=%0d)", avm_readdata, cycles);
	if(DDRAM_RD && rd_count < 40) $display("DDRRD  qaddr=%07x burst=%0d  (t=%0d)", DDRAM_ADDR, DDRAM_BURSTCNT, cycles);
	if(DDRAM_DOUT_READY && rd_count < 40) $display("DDRDAT %016x  (t=%0d)", DDRAM_DOUT, cycles);

	if(avm_write && !avm_waitrequest) begin
		ram_write_count <= ram_write_count + 1;
		if(ram_write_count < 100) $display("MEMW %08x <= %08x be=%x wr_eip=%08x  (t=%0d)", {avm_address,2'b00}, avm_writedata, avm_byteenable, ao486.pipeline_inst.wr_eip, cycles);
	end
end

integer k, p;
initial begin
	reset = 0;
	repeat (10) @(posedge clk);
	reset = 1;
	repeat (20) @(posedge clk);
	reset = 0;
	$display("reset released");

	for(cycles = 0; cycles < CYCLES_MAX; cycles = cycles + 1) @(posedge clk);

	$display("");
	$display("==== TIMEOUT after %0d cycles ====", CYCLES_MAX);
	$display("io ops: %0d   ram writes: %0d   mem reads: %0d", io_count, ram_write_count, rd_count);
	$display("");
	$display("---- last %0d io ops (oldest first) ----", TRACE_TAIL);
	for(k = 0; k < TRACE_TAIL; k = k + 1) begin
		p = (io_tail_pos + k) % TRACE_TAIL;
		if(io_tail_iswr[p]) $display("IOW %04x <= %02x", io_tail_addr[p], io_tail_data[p]);
		else                $display("IOR %04x => %02x", io_tail_addr[p], io_tail_data[p]);
	end
	$display("");
	$display("---- last %0d mem read addrs (oldest first) ----", TRACE_TAIL);
	for(k = 0; k < TRACE_TAIL; k = k + 1) begin
		p = (rd_tail_pos + k) % TRACE_TAIL;
		$display("R %08x", rd_tail_addr[p]);
	end
	$display("");
	$display("---- last 256 distinct exe_eip (oldest first) ----");
	for(k = 0; k < 256; k = k + 1) begin
		p = (eip_tail_pos + k) % 256;
		$display("XEIP %08x", eip_tail[p]);
	end
	$finish;
end

endmodule
