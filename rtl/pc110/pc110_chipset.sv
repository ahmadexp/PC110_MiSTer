// IBM Palm Top PC 110 board-specific I/O.
//
// This module models only state that is outside the standard PC/AT devices in
// ao486.  Defaults come from the read-only 2026 hardware captures in
// Open-Source-PC110/Discovery/Chipset and Discovery/Pluto.  The EC/ED bank is
// the VL82C420 shadow/cache bank, not the power MCU mailbox used by older
// PC110-EMU revisions.

module pc110_chipset
(
	input  logic        clk,
	input  logic        reset,

	input  logic [15:0] io_address,
	input  logic        io_read,
	input  logic        io_write,
	input  logic  [7:0] io_writedata,
	output logic  [7:0] io_readdata,
	output logic        io_cs,

	// One bit per 16 KiB block, C0000 first and FFFFF last.  In each
	// VL82C420 AXS two-bit field, bit 0 controls writes to shadow RAM and
	// bit 1 selects shadow RAM for reads.
	output logic [15:0] shadow_write_enable,
	output logic [15:0] shadow_read_enable,
	output logic  [7:0] romset,

	output logic  [6:0] font_bank_select,
	output logic  [7:0] font_window_segment,
	output logic        font_window_enable,

	// VL82C420 EC/ED RAMCFG0 (index 02h).  POST's DRAM bank sizer writes
	// candidate row-configuration codes here and expects the array's
	// aliasing behavior to follow; 0Bh is the settled planar value
	// captured from live hardware.
	output logic  [7:0] dram_cfg0,

	// POST diagnostic logger: every write to the BIOS progress port
	// (3BCh) and failure-code ports (190h/191h) is streamed out this
	// UART line at 115200 baud as a tag byte ('P', 'E', 'e') followed
	// by the code byte.  Idle high.
	output logic        postlog_tx,

	// value returned on the shared I/O read bus, for the ATA trace
	input  logic  [7:0] io_snoop
);

	// clk_sys is 30 MHz; 30e6 / 115200 = 260.42
	localparam int unsigned POSTLOG_DIV = 260;

	logic [7:0] scamp [0:127];
	logic [7:0] block2[0:255];
	logic [7:0] eced [0:63];
	logic [7:0] pcic [0:127];
	logic [7:0] ecb [0:31];
	logic [7:0] pos [0:7];
	logic [7:0] xr [0:127];
	logic [6:0] xr_index;
	logic       vstat_flip;

	logic [6:0] scamp_index;
	logic [7:0] block2_index;
	logic [5:0] eced_index;
	logic [6:0] pcic_index;
	logic [4:0] ecb_index;
	logic [7:0] font_bank;
	logic [7:0] font_segment;
	logic       font_enable;
	logic [7:0] ink_control;
	logic [7:0] planar_setup;
	logic [7:0] planar_control;
	logic [7:0] cfg22;
	logic [7:0] cfg23;
	logic       scamp_gate;
	logic       block2_gate;
	logic       eced_gate;
	logic [2:0] block2_unlock_step;

	assign font_bank_select = font_bank[6:0];
	assign font_window_segment = font_segment;
	assign font_window_enable = font_enable;
	assign dram_cfg0 = eced[8'h02];

	integer i;
	initial begin
		for(i = 0; i < 128; i = i + 1) scamp[i] = 8'h00;
		for(i = 0; i < 256; i = i + 1) block2[i] = 8'hFF;
		for(i = 0; i < 64;  i = i + 1) eced[i] = 8'h00;
		for(i = 0; i < 128; i = i + 1) pcic[i] = 8'h00;
		for(i = 0; i < 32;  i = i + 1) ecb[i] = 8'hFF;
		for(i = 0; i < 8;   i = i + 1) pos[i] = 8'h00;

		// VL82C420 runtime view, captured through 74h/76h.
		scamp[8'h00] = 8'h00; scamp[8'h01] = 8'hBB;
		scamp[8'h02] = 8'h80; scamp[8'h03] = 8'h00;
		for(i = 4; i < 13; i = i + 1) scamp[i] = 8'hFF;
		scamp[8'h0D] = 8'h6F; scamp[8'h0E] = 8'h7E;
		scamp[8'h0F] = 8'h50; scamp[8'h10] = 8'h80;
		scamp[8'h13] = 8'h90; scamp[8'h14] = 8'hF0;
		scamp[8'h15] = 8'hE4; scamp[8'h16] = 8'hA1;
		scamp[8'h20] = 8'h8E; scamp[8'h21] = 8'h02;
		scamp[8'h2E] = 8'h98; scamp[8'h2F] = 8'h8A;
		scamp[8'h30] = 8'h10; scamp[8'h31] = 8'h14;
		scamp[8'h32] = 8'h10; scamp[8'h33] = 8'h20;
		scamp[8'h34] = 8'h08; scamp[8'h35] = 8'hBA;
		scamp[8'h36] = 8'h9E; scamp[8'h37] = 8'hF1;
		scamp[8'h38] = 8'h5A; scamp[8'h39] = 8'h50;
		scamp[8'h3A] = 8'hF1; scamp[8'h3B] = 8'h3C;
		scamp[8'h3C] = 8'h0A; scamp[8'h3D] = 8'h1E;
		scamp[8'h3E] = 8'h2C; scamp[8'h3F] = 8'h01;
		scamp[8'h40] = 8'h02; scamp[8'h41] = 8'h05;
		scamp[8'h42] = 8'h01; scamp[8'h43] = 8'h88;
		scamp[8'h44] = 8'h03;
		scamp[8'h49] = 8'h0A; scamp[8'h4A] = 8'h03;
		scamp[8'h4B] = 8'h88; scamp[8'h4C] = 8'h05;
		scamp[8'h50] = 8'h08; scamp[8'h51] = 8'h1E;
		scamp[8'h52] = 8'h11; scamp[8'h53] = 8'h88;
		scamp[8'h54] = 8'h11;
		scamp[8'h58] = 8'h0C; scamp[8'h5B] = 8'h88;
		scamp[8'h76] = 8'h10; scamp[8'h77] = 8'h4F;
		scamp[8'h78] = 8'h0F; scamp[8'h79] = 8'h10;
		scamp[8'h7A] = 8'h53; scamp[8'h7B] = 8'h4C;
		scamp[8'h7D] = 8'h10; scamp[8'h7E] = 8'h15;
		scamp[8'h7F] = 8'hEE;

		// VL82C420 POST/programming view, captured through 24h/25h.
		for(i = 0; i < 8; i = i + 1) block2[i] = 8'hAA;
		block2[8'h08] = 8'h40; block2[8'h09] = 8'h41;
		block2[8'h0A] = 8'h42; block2[8'h0B] = 8'h43;
		block2[8'h0E] = 8'h00; block2[8'h0F] = 8'h0F;
		for(i = 8'h10; i <= 8'h15; i = i + 1) block2[i] = 8'h00;
		block2[8'h22] = 8'h11; block2[8'h23] = 8'h08;
		block2[8'h24] = 8'h04; block2[8'h25] = 8'h01;
		block2[8'h26] = 8'h00; block2[8'h27] = 8'h20;
		block2[8'h28] = 8'h0B; block2[8'h29] = 8'h0C;
		block2[8'h2A] = 8'h00; block2[8'h2B] = 8'h08;
		block2[8'h2E] = 8'h80;
		block2[8'h40] = 8'h00; block2[8'h41] = 8'h00;
		block2[8'h42] = 8'h12; block2[8'h43] = 8'h00;
		block2[8'h44] = 8'h50; block2[8'h45] = 8'h05;
		block2[8'h4E] = 8'h00;
		block2[8'h60] = 8'h00; block2[8'h61] = 8'h01;
		block2[8'h62] = 8'h00; block2[8'h65] = 8'h00;
		block2[8'h66] = 8'h00; block2[8'h70] = 8'h02;
		block2[8'h84] = 8'hEE; block2[8'h85] = 8'h15;
		for(i = 8'h90; i <= 8'h97; i = i + 1) block2[i] = 8'hAA;
		block2[8'h98] = 8'hC0; block2[8'h99] = 8'h41;
		block2[8'h9A] = 8'h42; block2[8'h9B] = 8'h43;
		block2[8'h9C] = 8'hAA; block2[8'h9D] = 8'hAA;
		block2[8'h9E] = 8'h00; block2[8'h9F] = 8'h0E;
		block2[8'hA2] = 8'h11; block2[8'hA3] = 8'h70;
		block2[8'hA4] = 8'h02; block2[8'hA5] = 8'h01;
		block2[8'hA6] = 8'h00; block2[8'hA7] = 8'h20;
		block2[8'hA8] = 8'h0B;
		block2[8'hB0] = 8'hBA; block2[8'hB1] = 8'h9E;
		block2[8'hB2] = 8'hF0; block2[8'hB3] = 8'h5A;
		block2[8'hB4] = 8'h50; block2[8'hB5] = 8'hF5;
		block2[8'hB6] = 8'hDA; block2[8'hB7] = 8'h00;
		block2[8'hB8] = 8'h00; block2[8'hB9] = 8'h40;
		block2[8'hBA] = 8'h00; block2[8'hBB] = 8'h00;
		block2[8'hBC] = 8'h02; block2[8'hBE] = 8'h10;
		block2[8'hBF] = 8'h14;
		block2[8'hC0] = 8'h00; block2[8'hC1] = 8'h00;
		block2[8'hC2] = 8'h00; block2[8'hC8] = 8'hF2;
		block2[8'hC9] = 8'h03; block2[8'hCA] = 8'hA1;
		block2[8'hCB] = 8'h02;
		block2[8'hD0] = 8'h60; block2[8'hD1] = 8'h00;
		block2[8'hD2] = 8'h24; block2[8'hD3] = 8'h00;
		block2[8'hD8] = 8'h00; block2[8'hD9] = 8'h00;
		block2[8'hDA] = 8'h20; block2[8'hDB] = 8'h00;
		block2[8'hE0] = 8'h00; block2[8'hE1] = 8'h00;
		block2[8'hE2] = 8'h00; block2[8'hE8] = 8'hF4;
		block2[8'hE9] = 8'h03; block2[8'hEA] = 8'hA1;
		block2[8'hEB] = 8'h02;
		block2[8'hF0] = 8'h80; block2[8'hF1] = 8'h00;
		block2[8'hF2] = 8'h00; block2[8'hF3] = 8'h00;
		block2[8'hF4] = 8'h10; block2[8'hF5] = 8'h20;
		block2[8'hF6] = 8'h08; block2[8'hF7] = 8'h07;
		block2[8'hF8] = 8'h0E; block2[8'hFB] = 8'h18;
		block2[8'hFC] = 8'hE0; block2[8'hFE] = 8'h3F;
		block2[8'hFF] = 8'h00;

		// VL82C420 shadow/cache/ROM-decode bank, EC/ED.
		eced[8'h00] = 8'h42; eced[8'h01] = 8'hD5;
		eced[8'h02] = 8'h0B; eced[8'h03] = 8'h00;
		eced[8'h04] = 8'h06; eced[8'h05] = 8'hA8;
		eced[8'h06] = 8'h1A; eced[8'h07] = 8'hEC;
		eced[8'h08] = 8'h38; eced[8'h0A] = 8'h03;
		eced[8'h0C] = 8'h29; eced[8'h0F] = 8'h2A;
		eced[8'h12] = 8'hAA; eced[8'h13] = 8'h55;
		eced[8'h14] = 8'h55; eced[8'h15] = 8'h6A;
		eced[8'h16] = 8'h55; eced[8'h17] = 8'h55;
		eced[8'h18] = 8'hAA; eced[8'h19] = 8'h1A;
		eced[8'h1A] = 8'h04; eced[8'h1B] = 8'h08;
		eced[8'h1C] = 8'h74; eced[8'h24] = 8'hFF;
		eced[8'h25] = 8'hFF; eced[8'h26] = 8'hFF;
		eced[8'h27] = 8'hFF; eced[8'h28] = 8'hFF;
		eced[8'h29] = 8'hFF; eced[8'h2A] = 8'hFF;
		eced[8'h2B] = 8'hFF; eced[8'h37] = 8'h10;

		// C&T F65535 extension registers (XR), index/data at 3D6h/3D7h.
		// Live text-mode capture from the running PC110; XR00 = C1h is the
		// chip identity (chipcode Ch = F65535, revision 1) and XR70 = 00h
		// keeps the 3C3/46E8 enable path accessible.
		for(i = 0; i < 128; i = i + 1) xr[i] = 8'h00;
		xr[8'h00] = 8'hC1; xr[8'h01] = 8'hDE;
		xr[8'h02] = 8'h01; xr[8'h03] = 8'h02;
		xr[8'h04] = 8'h81; xr[8'h06] = 8'hC2;
		xr[8'h08] = 8'hF8; xr[8'h0E] = 8'h80;
		xr[8'h0F] = 8'h01; xr[8'h18] = 8'hFF;
		xr[8'h19] = 8'h56; xr[8'h1A] = 8'h13;
		xr[8'h1B] = 8'h5F; xr[8'h1C] = 8'h4F;
		xr[8'h1D] = 8'h7F; xr[8'h1E] = 8'hFF;
		xr[8'h1F] = 8'h02; xr[8'h28] = 8'h80;
		xr[8'h29] = 8'h4C; xr[8'h2B] = 8'h03;
		xr[8'h2C] = 8'h04; xr[8'h2D] = 8'h50;
		xr[8'h2E] = 8'h50; xr[8'h30] = 8'h05;
		xr[8'h31] = 8'h14; xr[8'h32] = 8'h13;
		xr[8'h33] = 8'h40; xr[8'h51] = 8'hC4;
		xr[8'h52] = 8'h42; xr[8'h54] = 8'hC0;
		xr[8'h55] = 8'hE5; xr[8'h57] = 8'h23;
		xr[8'h60] = 8'h88; xr[8'h61] = 8'h2E;

		// Ricoh RB5C396 / 82365-compatible controller.  Both sockets start
		// empty; software can program the remaining ExCA register file.
		pcic[8'h00] = 8'h83; pcic[8'h01] = 8'h33;
		pcic[8'h02] = 8'h40; pcic[8'h06] = 8'h20;
		pcic[8'h40] = 8'h83; pcic[8'h41] = 8'h33;
		pcic[8'h42] = 8'h40; pcic[8'h46] = 8'h20;

		// EC-B live defaults.  Index is masked to five bits.
		ecb[8'h00] = 8'h00; ecb[8'h02] = 8'hF5;
		ecb[8'h04] = 8'h84; ecb[8'h05] = 8'hF3;
		ecb[8'h06] = 8'h6C; ecb[8'h07] = 8'hFD;
		ecb[8'h09] = 8'hF7; ecb[8'h0B] = 8'hFC;
		ecb[8'h13] = 8'hE8; ecb[8'h14] = 8'h35;
		ecb[8'h15] = 8'h04;

		// POS register 2 bit 0 enables the planar VGA.
		pos[2] = 8'h01;
	end

	// ROMSET (EC/ED index 0Ch) value 00h opens the whole upper-memory
	// shadow window for writes; POST wraps its C-segment copy and the
	// video BIOS decompression in ROMSET open/relock.  Any other value
	// defers to the per-16KiB xAXS write bits.
	wire shadow_open_all = (eced[8'h0C] == 8'h00);
	assign romset = eced[8'h0C];

	generate
		genvar g;
		for(g = 0; g < 4; g = g + 1) begin : g_shadow_decode
			assign shadow_write_enable[(g*4)+0] = shadow_open_all | eced[8'h0F+g][0];
			assign shadow_write_enable[(g*4)+1] = shadow_open_all | eced[8'h0F+g][2];
			assign shadow_write_enable[(g*4)+2] = shadow_open_all | eced[8'h0F+g][4];
			assign shadow_write_enable[(g*4)+3] = shadow_open_all | eced[8'h0F+g][6];
			assign shadow_read_enable[(g*4)+0]  = eced[8'h0F+g][1];
			assign shadow_read_enable[(g*4)+1]  = eced[8'h0F+g][3];
			assign shadow_read_enable[(g*4)+2]  = eced[8'h0F+g][5];
			assign shadow_read_enable[(g*4)+3]  = eced[8'h0F+g][7];
		end
	endgenerate

	always_comb begin
		io_cs = 1'b1;
		case(io_address)
			16'h0022, 16'h0023: io_readdata = (io_address[0] ? cfg23 : cfg22);
			16'h0024: io_readdata = 8'hFF;
			16'h0025: io_readdata = block2_gate ? block2[block2_index] : 8'hFF;
			16'h004F: io_readdata = 8'hFF; // confirmed I/O-delay port
			16'h0074: io_readdata = 8'hFF;
			// Index 0 (and 1) of this bank are readable even while the
			// SCAMP config gate is locked: POST's memory-config check at
			// F000:4347 reads index 0 (bits[1:0] must be clear) and the
			// memory sizer reads index 1 without opening the 22h/23h gate.
			// Returning 0xFF there makes bits[1:0]=1 -> spurious 221 error,
			// which then blocks disk boot.  scamp[0]=00h, scamp[1]=BBh.
			16'h0076: io_readdata = (scamp_gate || scamp_index <= 7'h01) ?
			                        scamp[scamp_index] : 8'hFF;
			16'h0094: io_readdata = planar_setup;
			16'h0098: io_readdata = planar_control;
			16'h00EC: io_readdata = 8'hFF;
			16'h00ED: io_readdata = eced_gate ? eced[eced_index] : 8'hFF;
			16'h00F9, 16'h00FB: io_readdata = 8'hFF;
			16'h0100, 16'h0101, 16'h0102, 16'h0103,
			16'h0104, 16'h0105, 16'h0106, 16'h0107:
				io_readdata = (planar_setup == 8'hDF) ? pos[io_address[2:0]] : 8'hFF;
			16'h03D6: io_readdata = {1'b0, xr_index};
			16'h03D7: io_readdata = xr[xr_index];
			// Input Status 1 shim: vertical-retrace bit 3 toggles on every
			// read and display-enable bit 0 stays set, exactly the behavior
			// the PC110-EMU oracle uses to satisfy the video BIOS retrace
			// waits.  vga.v still sees the read for its flip-flop side
			// effects; this only overrides the returned data.
			16'h03DA, 16'h03BA: io_readdata = {4'h0, vstat_flip, 2'b00, 1'b1};
			16'h03E0: io_readdata = 8'hFF;
			16'h03E1: io_readdata = pcic[pcic_index];
			16'h1160: io_readdata = {1'b0, font_bank[6:0]};
			16'h1161: io_readdata = 8'hFF;
			16'h1162: io_readdata = font_segment;
			16'h1163: io_readdata = {7'h00, font_enable};
			16'h15E0: io_readdata = 8'h00;
			16'h15E1: io_readdata = (ink_control == 8'h38) ? 8'h7F : 8'hFF;
			16'h15E2: io_readdata = ink_control;
			16'h15E3, 16'h15E4, 16'h15E5, 16'h15E6, 16'h15E7:
				io_readdata = 8'hFF;
			16'h15E8: io_readdata = 8'h64;
			16'h15E9, 16'h15EA, 16'h15EB: io_readdata = 8'hFF;
			16'h15EC: io_readdata = 8'h48;
			16'h15ED: io_readdata = 8'hFF;
			16'h15EE: io_readdata = 8'h80;
			16'h15EF: io_readdata = 8'h00;
			16'h35EA: io_readdata = 8'hFF;
			16'h35EB: io_readdata = ecb[ecb_index];
			16'hFC23, 16'hF023, 16'hC023: io_readdata = 8'hFF;
			default: begin
				io_readdata = 8'hFF;
				io_cs = 1'b0;
			end
		endcase
	end

	always_ff @(posedge clk) begin
		if(reset) begin
			scamp_index       <= 7'h00;
			block2_index      <= 8'h00;
			eced_index        <= 6'h00;
			pcic_index        <= 7'h00;
			ecb_index         <= 5'h00;
			font_bank         <= 8'h00;
			font_segment      <= 8'hDE;
			font_enable       <= 1'b1;
			ink_control       <= 8'hC0;
			planar_setup      <= 8'hFF;
			planar_control    <= 8'h00;
			cfg22             <= 8'h00;
			cfg23             <= 8'h01;
			scamp_gate        <= 1'b0;
			block2_gate       <= 1'b0;
			eced_gate         <= 1'b0;
			block2_unlock_step <= 3'd0;
		end
		else begin
			if(io_read) begin
				case(block2_unlock_step)
					3'd0: block2_unlock_step <= (io_address == 16'hFC23) ? 3'd1 : 3'd0;
					3'd1: block2_unlock_step <= (io_address == 16'hF023) ? 3'd2 :
					                            (io_address == 16'hFC23) ? 3'd1 : 3'd0;
					3'd2: block2_unlock_step <= (io_address == 16'hC023) ? 3'd3 : 3'd0;
					3'd3: begin
						block2_unlock_step <= 3'd0;
						if(io_address == 16'h0023) block2_gate <= 1'b1;
					end
					default: block2_unlock_step <= 3'd0;
				endcase
			end

			if(io_write) begin
				case(io_address)
					16'h0022: begin
						cfg22 <= io_writedata;
						if((io_writedata == 8'h80) && (cfg23 == 8'h00))
							scamp_gate <= 1'b1;
					end
					16'h0023: begin
						cfg23 <= io_writedata;
						if(io_writedata[0]) begin
							scamp_gate  <= 1'b0;
							block2_gate <= 1'b0;
						end
					end
					16'h0024: block2_index <= io_writedata;
					16'h0025: if(block2_gate) block2[block2_index] <= io_writedata;
					16'h0074: scamp_index <= io_writedata[6:0];
					16'h0076: if(scamp_gate) scamp[scamp_index] <= io_writedata;
					16'h0094: planar_setup <= io_writedata;
					16'h0098: planar_control <= io_writedata;
					16'h00EC: eced_index <= io_writedata[5:0];
					16'h00ED: if(eced_gate) eced[eced_index] <= io_writedata;
					16'h00FB: eced_gate <= 1'b1;
					16'h00F9: eced_gate <= 1'b0;
					16'h0100, 16'h0101, 16'h0102, 16'h0103,
					16'h0104, 16'h0105, 16'h0106, 16'h0107:
						if(planar_setup == 8'hDF) pos[io_address[2:0]] <= io_writedata;
					16'h03D6: xr_index <= io_writedata[6:0];
					16'h03D7: if(xr_index != 7'h00) xr[xr_index] <= io_writedata;
					16'h03E0: pcic_index <= io_writedata[6:0];
					16'h03E1: if((pcic_index[5:0] != 6'h00))
						pcic[pcic_index] <= io_writedata;
					16'h1160: font_bank <= {1'b0, io_writedata[6:0]};
					16'h1162: font_segment <= io_writedata;
					16'h1163: font_enable <= io_writedata[0];
					16'h15E2: ink_control <= io_writedata;
					16'h35EA: ecb_index <= io_writedata[4:0];
					16'h35EB: ecb[ecb_index] <= io_writedata;
					default: ;
				endcase
			end
		end
	end

	// ------------------------------------------------------------------
	// POST diagnostic logger.  Snoops writes to 3BCh/190h/191h (these
	// remain outside io_cs so other decode is unaffected) into a small
	// FIFO of {tag, code} pairs drained by a 115200-baud UART transmitter.

	// Input Status 1 toggle: one flip per completed read of 3DAh/3BAh.
	logic io_read_d;
	logic [7:0] ata_status_reads;
	logic [7:0] ata_last_status = 8'hDE;
	logic [7:0] ata_last_err = 8'hDE;
	logic [6:0] cmos_sel;
	always_ff @(posedge clk) begin
		io_read_d <= io_read;
		if(reset) vstat_flip <= 1'b0;
		else if(io_read && !io_read_d &&
		        (io_address == 16'h03DA || io_address == 16'h03BA))
			vstat_flip <= ~vstat_flip;
		if(reset) ata_status_reads <= 8'd0;
		else if(io_read && !io_read_d && io_address == 16'h01F7)
			ata_status_reads <= ata_status_reads + 1'd1;
		// track the CMOS/RTC index the guest last selected via port 70h,
		// so 71h reads can be attributed to a specific CMOS byte
		if(reset) cmos_sel <= 7'd0;
		else if(io_write && !io_write_d && io_address == 16'h0070)
			cmos_sel <= io_writedata[6:0];
	end

	logic [15:0] plog_fifo [0:511];
	logic  [8:0] plog_head, plog_tail;
	logic        io_write_d;

	always_ff @(posedge clk) begin
		io_write_d <= io_write;
		if(reset) begin
			plog_tail <= 9'd0;
		end
		else if(io_write && !io_write_d) begin
			case(io_address)
				16'h03BC: begin plog_fifo[plog_tail] <= {8'h50, io_writedata}; plog_tail <= plog_tail + 1'd1; end // 'P' progress
				16'h0190: begin plog_fifo[plog_tail] <= {8'h45, io_writedata}; plog_tail <= plog_tail + 1'd1; end // 'E' failure hi
				16'h0191: begin plog_fifo[plog_tail] <= {8'h65, io_writedata}; plog_tail <= plog_tail + 1'd1; end // 'e' failure lo
				// video BIOS progress: C&T extension index writes ('X') mean
				// the 32 KiB runtime image decompressed and init body started
				16'h03D6: begin plog_fifo[plog_tail] <= {8'h58, io_writedata}; plog_tail <= plog_tail + 1'd1; end
				// ATA task-file trace: command bytes ('D'), device control
				// ('d'), and every 1F1h-1F6h register write (tag C1h-C6h)
				// reconstruct the BIOS's drive-detection conversation.
				16'h01F7: begin plog_fifo[plog_tail] <= {8'h44, io_writedata}; plog_tail <= plog_tail + 1'd1; end
				16'h03F6: begin plog_fifo[plog_tail] <= {8'h64, io_writedata}; plog_tail <= plog_tail + 1'd1; end
				16'h01F1, 16'h01F2, 16'h01F3,
				16'h01F4, 16'h01F5, 16'h01F6: begin
					plog_fifo[plog_tail] <= {5'b11000, io_address[2:0], io_writedata};
					plog_tail <= plog_tail + 1'd1;
				end
				// shadow/ROM decode config as POST programs it: tag 80h|index
				16'h00ED: if(eced_gate && eced_index >= 6'h0C && eced_index <= 6'h12) begin
					plog_fifo[plog_tail] <= {{2'b10, eced_index}, io_writedata};
					plog_tail <= plog_tail + 1'd1;
				end
				default: ;
			endcase
		end
		// log the value of every 1F7h status read when it changes (tag
		// 'v'), plus every 16th poll count (tag 'r'): reconstructs both
		// what the BIOS saw and how long it polled
		else if(io_read_d && !io_read && io_address == 16'h01F7 &&
		        io_snoop != ata_last_status) begin
			ata_last_status <= io_snoop;
			plog_fifo[plog_tail] <= {8'h76, io_snoop};
			plog_tail <= plog_tail + 1'd1;
		end
		else if(io_read && !io_read_d && io_address == 16'h01F7 &&
		        ata_status_reads[3:0] == 4'hF) begin
			plog_fifo[plog_tail] <= {8'h72, ata_status_reads};
			plog_tail <= plog_tail + 1'd1;
		end
		// error register (1F1h) reads (tag 'x'): the reset-signature detect
		// at F000:D1E0 requires 01h here; log its value when it changes
		else if(io_read_d && !io_read && io_address == 16'h01F1 &&
		        io_snoop != ata_last_err) begin
			ata_last_err <= io_snoop;
			plog_fifo[plog_tail] <= {8'h78, io_snoop};
			plog_tail <= plog_tail + 1'd1;
		end
		// signature register reads after reset (1F2 count, 1F4/1F5 cyl):
		// tag 's' with {addr[2:0], value nibble} so CHS signature is visible
		else if(io_read_d && !io_read &&
		        (io_address == 16'h01F2 || io_address == 16'h01F4 || io_address == 16'h01F5)) begin
			plog_fifo[plog_tail] <= {8'h73, io_address[3:0], io_snoop[3:0]};
			plog_tail <= plog_tail + 1'd1;
		end
		// keyboard data port 60h reads (tag 'K'): shows the scancodes the
		// guest receives from the 8042, proving keystrokes reach the core
		else if(io_read_d && !io_read && io_address == 16'h0060) begin
			plog_fifo[plog_tail] <= {8'h4B, io_snoop};
			plog_tail <= plog_tail + 1'd1;
		end
		// CMOS reads (port 71h) of the boot-order/diagnostic bytes: tag
		// 'C'=0Eh diag, 'c'=1Dh order-lo, 'i'=1Eh order-hi, so we can see
		// exactly what the INT19 boot-list builder reads
		else if(io_read_d && !io_read && io_address == 16'h0071 &&
		        (cmos_sel == 7'h0E || cmos_sel == 7'h1D || cmos_sel == 7'h1E)) begin
			plog_fifo[plog_tail] <= {(cmos_sel==7'h0E)?8'h43:(cmos_sel==7'h1D)?8'h63:8'h69, io_snoop};
			plog_tail <= plog_tail + 1'd1;
		end
	end

	logic [9:0]  plog_div;
	logic [3:0]  plog_bit;
	logic [9:0]  plog_shift;
	logic        plog_second;   // sending the code byte of the pair
	logic [7:0]  plog_code;

	always_ff @(posedge clk) begin
		if(reset) begin
			plog_head   <= 9'd0;
			plog_bit    <= 4'd0;
			plog_div    <= 10'd0;
			plog_second <= 1'b0;
			postlog_tx  <= 1'b1;
		end
		else if(plog_bit == 4'd0) begin
			postlog_tx <= 1'b1;
			if(plog_head != plog_tail || plog_second) begin
				if(plog_second) begin
					plog_shift <= {1'b1, plog_code, 1'b0};
				end
				else begin
					plog_shift <= {1'b1, plog_fifo[plog_head][15:8], 1'b0};
					plog_code  <= plog_fifo[plog_head][7:0];
					plog_head  <= plog_head + 1'd1;
				end
				plog_second <= ~plog_second;
				plog_bit    <= 4'd10;
				plog_div    <= 10'd0;
			end
		end
		else begin
			postlog_tx <= plog_shift[0];
			if(plog_div == POSTLOG_DIV[9:0] - 10'd1) begin
				plog_div   <= 10'd0;
				plog_shift <= {1'b1, plog_shift[9:1]};
				plog_bit   <= plog_bit - 4'd1;
			end
			else plog_div <= plog_div + 10'd1;
		end
	end

endmodule
