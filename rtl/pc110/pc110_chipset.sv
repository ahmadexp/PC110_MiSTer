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

	output logic  [6:0] font_bank_select,
	output logic  [7:0] font_window_segment,
	output logic        font_window_enable
);

	logic [7:0] scamp [0:127];
	logic [7:0] block2[0:255];
	logic [7:0] eced [0:63];
	logic [7:0] pcic [0:127];
	logic [7:0] ecb [0:31];
	logic [7:0] pos [0:7];

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

	generate
		genvar g;
		for(g = 0; g < 4; g = g + 1) begin : g_shadow_decode
			assign shadow_write_enable[(g*4)+0] = eced[8'h0F+g][0];
			assign shadow_write_enable[(g*4)+1] = eced[8'h0F+g][2];
			assign shadow_write_enable[(g*4)+2] = eced[8'h0F+g][4];
			assign shadow_write_enable[(g*4)+3] = eced[8'h0F+g][6];
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
			16'h0076: io_readdata = scamp_gate ? scamp[scamp_index] : 8'hFF;
			16'h0094: io_readdata = planar_setup;
			16'h0098: io_readdata = planar_control;
			16'h00EC: io_readdata = 8'hFF;
			16'h00ED: io_readdata = eced_gate ? eced[eced_index] : 8'hFF;
			16'h00F9, 16'h00FB: io_readdata = 8'hFF;
			16'h0100, 16'h0101, 16'h0102, 16'h0103,
			16'h0104, 16'h0105, 16'h0106, 16'h0107:
				io_readdata = (planar_setup == 8'hDF) ? pos[io_address[2:0]] : 8'hFF;
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

endmodule
