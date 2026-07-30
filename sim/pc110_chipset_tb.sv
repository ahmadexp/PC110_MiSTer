`timescale 1ns/1ps

module pc110_chipset_tb;
	logic clk = 0;
	logic reset = 1;
	logic [15:0] io_address = 0;
	logic io_read = 0;
	logic io_write = 0;
	logic [7:0] io_writedata = 0;
	logic [7:0] io_readdata;
	logic io_cs;
	logic [15:0] shadow_we;
	logic [15:0] shadow_re;
	logic [6:0] font_bank;
	logic [7:0] font_segment;
	logic font_enable;
	logic postlog_tx;
	logic kbd_hide;
	logic ckpt_boot;

	always #5 clk = ~clk;

	pc110_chipset dut
	(
		.clk(clk),
		.reset(reset),
		.io_address(io_address),
		.io_read(io_read),
		.io_write(io_write),
		.io_writedata(io_writedata),
		.io_readdata(io_readdata),
		.io_cs(io_cs),
		.shadow_write_enable(shadow_we),
		.shadow_read_enable(shadow_re),
		.font_bank_select(font_bank),
		.font_window_segment(font_segment),
		.font_window_enable(font_enable),
		.postlog_tx(postlog_tx),
		.io_snoop(8'hFF),
		.errlog_wr(1'b0),
		.errlog_tag(8'h00),
		.errlog_byte(8'h00),
		.kbd_hide(kbd_hide),
		.ckpt_boot(ckpt_boot)
	);

	task automatic write_port(input [15:0] port_num, input [7:0] value);
	begin
		@(negedge clk);
		io_address = port_num;
		io_writedata = value;
		io_write = 1;
		@(negedge clk);
		io_write = 0;
	end
	endtask

	task automatic read_port(input [15:0] port_num, output [7:0] value);
	begin
		@(negedge clk);
		io_address = port_num;
		io_read = 1;
		#1 value = io_readdata;
		@(negedge clk);
		io_read = 0;
	end
	endtask

	task automatic expect_read(
		input [15:0] port_num,
		input [7:0] expected,
		input [255:0] label_text
	);
		reg [7:0] actual;
	begin
		read_port(port_num, actual);
		if(actual !== expected)
			$fatal(1, "%s: port %04x returned %02x, expected %02x",
				label_text, port_num, actual, expected);
	end
	endtask

	initial begin
		repeat(3) @(posedge clk);
		reset = 0;

		if(postlog_tx !== 1'b1)
			$fatal(1, "POST logger UART must idle high");

		// Checkpoint tracking remains functional when the optional trace FIFO
		// is compiled out of the release build.
		write_port(16'h0190, 8'h56);
		if(kbd_hide !== 1'b1 || ckpt_boot !== 1'b0)
			$fatal(1, "early keyboard checkpoint decode mismatch");
		write_port(16'h0190, 8'h6E);
		if(kbd_hide !== 1'b0 || ckpt_boot !== 1'b1)
			$fatal(1, "boot checkpoint decode mismatch");

		// PCIC is visible without a gate and identifies both sockets.
		write_port(16'h03E0, 8'h00);
		expect_read(16'h03E1, 8'h83, "PCIC socket A ID");
		write_port(16'h03E0, 8'h01);
		expect_read(16'h03E1, 8'h3F, "PCIC socket A interface status");
		write_port(16'h03E0, 8'h40);
		expect_read(16'h03E1, 8'h83, "PCIC socket B ID");
		write_port(16'h03E0, 8'h41);
		expect_read(16'h03E1, 8'h33, "PCIC socket B interface status");
		write_port(16'h03E0, 8'h8B);
		write_port(16'h03E1, 8'hA5);
		expect_read(16'h03E1, 8'hA5, "PCIC extended register");
		write_port(16'h03E0, 8'h0B);
		expect_read(16'h03E1, 8'h00, "PCIC extended index does not alias");
		write_port(16'h03E0, 8'h56);
		write_port(16'h03E1, 8'h20);
		expect_read(16'h03E1, 8'h00, "PCIC software detect is write-only");
		write_port(16'h03E0, 8'h44);
		expect_read(16'h03E1, 8'h08, "PCIC card-detect change latch");
		expect_read(16'h03E1, 8'h00, "PCIC change latch clears on read");

		// PC110 LPT1 uses the historical 03BCh base.
		write_port(16'h03BC, 8'hA5);
		expect_read(16'h03BC, 8'hA5, "LPT data latch");
		expect_read(16'h03BD, 8'hD0, "LPT ready status");
		write_port(16'h03BE, 8'h05);
		expect_read(16'h03BE, 8'hE5, "LPT control latch");
		write_port(16'h03BE, 8'h04);
		expect_read(16'h03BD, 8'h90, "LPT acknowledge pulse");
		expect_read(16'h03BD, 8'hD0, "LPT acknowledge release");

		// SCAMP runtime view stays hidden until the write-based gate.
		write_port(16'h0074, 8'h7A);
		expect_read(16'h0076, 8'hFF, "SCAMP locked");
		write_port(16'h0023, 8'h00);
		write_port(16'h0022, 8'h80);
		expect_read(16'h0076, 8'h53, "SCAMP SL signature");
		write_port(16'h0023, 8'h01);
		expect_read(16'h0076, 8'hFF, "SCAMP relocked");

		// block2 requires the exact four-read enable sequence.
		write_port(16'h0024, 8'hB8);
		expect_read(16'h0025, 8'hFF, "block2 locked");
		expect_read(16'hFC23, 8'hFF, "block2 key 1");
		expect_read(16'hF023, 8'hFF, "block2 key 2");
		expect_read(16'hC023, 8'hFF, "block2 key 3");
		expect_read(16'h0023, 8'h01, "block2 key 4");
		expect_read(16'h0025, 8'h00, "block2 resume strap");

		// EC/ED gate controls shadow registers. AA means read-shadow,
		// write-protected; FF unlocks all four F-segment blocks.
		write_port(16'h00EC, 8'h12);
		expect_read(16'h00ED, 8'hFF, "ECED locked");
		write_port(16'h00FB, 8'h00);
		expect_read(16'h00ED, 8'hAA, "F shadow default");
		if(shadow_we[15:12] !== 4'b0000 || shadow_re[15:12] !== 4'b1111)
			$fatal(1, "F shadow decode mismatch: WE=%b RE=%b",
				shadow_we[15:12], shadow_re[15:12]);
		write_port(16'h00ED, 8'hFF);
		if(shadow_we[15:12] !== 4'b1111 || shadow_re[15:12] !== 4'b1111)
			$fatal(1, "F shadow unlock mismatch: WE=%b RE=%b",
				shadow_we[15:12], shadow_re[15:12]);
		write_port(16'h00EC, 8'h0F);
		write_port(16'h00ED, 8'h55);
		if(shadow_we[3:0] !== 4'b1111 || shadow_re[3:0] !== 4'b0000)
			$fatal(1, "C copy-state mismatch: WE=%b RE=%b",
				shadow_we[3:0], shadow_re[3:0]);
		write_port(16'h00F9, 8'h00);
		expect_read(16'h00ED, 8'hFF, "ECED relocked");

		// Font aperture controls and digitizer idle/enable behavior.
		expect_read(16'h1162, 8'hDE, "font aperture segment");
		if(font_bank !== 7'h00 || font_segment !== 8'hDE || font_enable !== 1'b1)
			$fatal(1, "font aperture outputs mismatch");
		expect_read(16'h15E1, 8'hFF, "inking disabled");
		write_port(16'h15E2, 8'h38);
		expect_read(16'h15E1, 8'h7F, "inking enabled");

		$display("PASS: PC110 chipset I/O, gates, and shadow decode");
		$finish;
	end
endmodule
