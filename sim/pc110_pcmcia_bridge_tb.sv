`timescale 1ns/1ps

module pc110_pcmcia_bridge_tb;
	logic clk = 0;
	logic reset = 1;
	logic io_cs = 0;
	logic [2:0] io_window = 0;
	logic [15:0] io_card_address = 0;
	logic io_read = 0;
	logic io_write = 0;
	logic [1:0] io_size = 0;
	logic [31:0] io_writedata = 0;
	logic [31:0] io_readdata;
	logic io_wait;
	logic mem_cs = 0;
	logic [2:0] mem_window = 0;
	logic [25:0] mem_card_address = 0;
	logic mem_attribute = 0;
	logic mem_read = 0;
	logic mem_write = 0;
	logic [31:0] mem_writedata = 0;
	logic [3:0] mem_byteenable = 0;
	logic [3:0] mem_burstcount = 1;
	logic [31:0] mem_readdata;
	logic mem_waitrequest;
	logic mem_readdatavalid;
	logic mem_active;
	logic [7:0] mgmt_address = 0;
	logic mgmt_read = 0;
	logic mgmt_write = 0;
	logic [15:0] mgmt_writedata = 0;
	logic [15:0] mgmt_readdata;
	logic request;
	logic backend_online;
	logic card_present;
	logic card_irq;

	always #5 clk = ~clk;

	pc110_pcmcia_bridge dut
	(
		.clk(clk), .reset(reset),
		.io_cs(io_cs), .io_window(io_window),
		.io_card_address(io_card_address), .io_read(io_read),
		.io_write(io_write), .io_size(io_size), .io_writedata(io_writedata),
		.io_readdata(io_readdata), .io_wait(io_wait),
		.mem_cs(mem_cs), .mem_window(mem_window),
		.mem_card_address(mem_card_address), .mem_attribute(mem_attribute),
		.mem_read(mem_read), .mem_write(mem_write),
		.mem_writedata(mem_writedata), .mem_byteenable(mem_byteenable),
		.mem_burstcount(mem_burstcount),
		.mem_readdata(mem_readdata), .mem_waitrequest(mem_waitrequest),
		.mem_readdatavalid(mem_readdatavalid), .mem_active(mem_active),
		.mgmt_address(mgmt_address), .mgmt_read(mgmt_read),
		.mgmt_write(mgmt_write), .mgmt_writedata(mgmt_writedata),
		.mgmt_readdata(mgmt_readdata), .request(request),
		.backend_online(backend_online), .card_present(card_present),
		.card_irq(card_irq)
	);

	task automatic mgmt_wr(input [7:0] address, input [15:0] value);
	begin
		@(negedge clk);
		mgmt_address = address;
		mgmt_writedata = value;
		mgmt_write = 1'b1;
		@(negedge clk);
		mgmt_write = 1'b0;
	end
	endtask

	initial begin
		repeat(3) @(posedge clk);
		reset = 0;

		// An enabled guest window with no physical backend completes as open
		// bus rather than deadlocking the CPU.
		@(negedge clk);
		io_cs = 1;
		io_read = 1;
		io_card_address = 16'h0002;
		#1;
		if(!io_wait) $fatal(1, "offline I/O wait was not asserted immediately");
		@(posedge clk);
		#1;
		if(request || io_readdata !== 32'hFFFFFFFF)
			$fatal(1, "offline I/O access did not complete as open bus");
		io_read = 0;
		io_cs = 0;
		repeat(2) @(posedge clk);

		// Bring the user-supplied host service online with a card present.
		mgmt_wr(8'h00, 16'h6000);
		if(!backend_online || !card_present)
			$fatal(1, "backend status write failed");

		io_cs = 1;
		io_window = 3'd1;
		io_card_address = 16'h0005;
		io_size = 2'd1;
		io_read = 1;
		@(posedge clk);
		#1;
		if(!request || !io_wait) $fatal(1, "I/O request was not held");
		mgmt_address = 8'h00;
		#1;
		if((mgmt_readdata & 16'h01FF) !== 16'h0051)
			$fatal(1, "I/O request status mismatch: %04x", mgmt_readdata);
		mgmt_address = 8'h01;
		#1;
		if(mgmt_readdata !== 16'h0005) $fatal(1, "I/O address mismatch");
		mgmt_address = 8'h05;
		#1;
		if(mgmt_readdata !== 16'h0003) $fatal(1, "I/O byte enable mismatch");

		mgmt_wr(8'h03, 16'hB5A5);
		mgmt_wr(8'h04, 16'h0000);
		mgmt_wr(8'h00, 16'h6001);
		#1;
		if(request || io_wait || io_readdata !== 32'h0000B5A5)
			$fatal(1, "I/O response acknowledgement failed");
		io_read = 0;
		io_cs = 0;
		repeat(2) @(posedge clk);

		// A burst memory request carries the ExCA window, card-relative
		// address, attribute/common selector, dword data, and byte enables.
		mem_cs = 1;
		mem_window = 3'd3;
		mem_card_address = 26'h0123456;
		mem_attribute = 1;
		mem_read = 1;
		mem_byteenable = 4'b0101;
		mem_burstcount = 4'd2;
		@(posedge clk);
		#1;
		if(!request || mem_waitrequest || !mem_active)
			$fatal(1, "memory read command was not offered for acceptance");
		@(posedge clk);
		#1;
		if(!mem_waitrequest) $fatal(1, "accepted memory burst was not held");
		mem_read = 0;
		mgmt_address = 8'h00;
		#1;
		if((mgmt_readdata & 16'h01FD) !== 16'h00ED)
			$fatal(1, "memory request status mismatch: %04x", mgmt_readdata);
		mgmt_address = 8'h01;
		#1;
		if(mgmt_readdata !== 16'h3456) $fatal(1, "memory address low mismatch");
		mgmt_address = 8'h02;
		#1;
		if(mgmt_readdata !== 16'h0012) $fatal(1, "memory address high mismatch");
		mgmt_address = 8'h05;
		#1;
		if(mgmt_readdata !== 16'h0005) $fatal(1, "memory byte enable mismatch");

		mgmt_wr(8'h03, 16'hBEEF);
		mgmt_wr(8'h04, 16'hCAFE);
		mgmt_wr(8'h00, 16'hE001);
		#1;
		if(!request || !mem_waitrequest || !mem_readdatavalid ||
		   mem_readdata !== 32'hCAFEBEEF || !card_irq)
			$fatal(1, "first memory burst response failed");
		mgmt_address = 8'h01;
		#1;
		if(mgmt_readdata !== 16'h345A)
			$fatal(1, "memory burst address did not advance");

		mgmt_wr(8'h03, 16'h5678);
		mgmt_wr(8'h04, 16'h1234);
		mgmt_wr(8'h00, 16'hE001);
		#1;
		if(request || mem_waitrequest || !mem_readdatavalid ||
		   mem_readdata !== 32'h12345678)
			$fatal(1, "final memory burst response failed");
		mem_cs = 0;
		@(posedge clk);

		$display("PASS: PC110 PCMCIA management bridge");
		$finish;
	end
endmodule
