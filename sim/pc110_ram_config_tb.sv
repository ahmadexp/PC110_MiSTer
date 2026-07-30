`timescale 1ns/1ps

module pc110_ram_config_tb;
	reg   [1:0] ram_option;
	wire [29:0] word_limit;
	wire [15:0] extmem_kb;
	wire [15:0] above16_64k;
	wire [15:0] checksum_sum;

	pc110_ram_config dut
	(
		.ram_option(ram_option),
		.word_limit(word_limit),
		.extmem_kb(extmem_kb),
		.above16_64k(above16_64k),
		.checksum_sum(checksum_sum)
	);

	task automatic check(input [1:0] option,
	                     input [29:0] expected_limit,
	                     input [15:0] expected_extmem,
	                     input [15:0] expected_above16,
	                     input [15:0] expected_sum);
	begin
		ram_option = option;
		#1;
		if(word_limit !== expected_limit || extmem_kb !== expected_extmem ||
		   above16_64k !== expected_above16 || checksum_sum !== expected_sum) begin
			$display("FAIL option %0d: limit=%08h ext=%04h above16=%04h sum=%04h",
			         option, word_limit, extmem_kb, above16_64k, checksum_sum);
			$fatal(1);
		end
	end
	endtask

	initial begin
		check(2'd0, 30'h00500000, 16'h4C00, 16'h0040, 16'h004C);
		check(2'd1, 30'h00100000, 16'h0C00, 16'h0000, 16'h000C);
		check(2'd2, 30'h00200000, 16'h1C00, 16'h0000, 16'h001C);
		check(2'd3, 30'h00300000, 16'h2C00, 16'h0000, 16'h002C);
		$display("PASS: PC110 RAM-module geometry");
		$finish;
	end
endmodule
