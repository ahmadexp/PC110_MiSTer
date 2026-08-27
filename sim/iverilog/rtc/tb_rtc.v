`timescale 1ns/1ps

module tb_rtc;

reg clk = 1'b0;
reg rst_n = 1'b0;

wire       irq;
reg        io_address = 1'b0;
reg        io_read = 1'b0;
wire [7:0] io_readdata;
reg        io_write = 1'b0;
reg  [7:0] io_writedata = 8'd0;

reg  [7:0] mgmt_address = 8'd0;
reg        mgmt_write = 1'b0;
reg  [7:0] mgmt_writedata = 8'd0;

localparam [27:0] CLOCK_RATE = 28'd8000;

rtc rtc_inst (
    .clk(clk),
    .rst_n(rst_n),
    .irq(irq),
    .io_address(io_address),
    .io_read(io_read),
    .io_readdata(io_readdata),
    .io_write(io_write),
    .io_writedata(io_writedata),
    .ram_option(2'd0),
    .bootcfg(6'd0),
    .setup_req(1'b0),
    .setup_ack(),
    .mgmt_address(mgmt_address),
    .mgmt_write(mgmt_write),
    .mgmt_writedata(mgmt_writedata),
    .clock_rate(CLOCK_RATE)
);

always #5 clk = ~clk;

task write_cmos;
    input [7:0] address;
    input [7:0] data;
    begin
        @(negedge clk);
        mgmt_address = address;
        mgmt_writedata = data;
        mgmt_write = 1'b1;
        @(negedge clk);
        mgmt_write = 1'b0;
    end
endtask

integer clocks_between_updates;
integer uip_clocks;

initial begin
    // MiSTer Main writes CMOS while the x86 core remains reset.
    write_cmos(8'h00, 8'h58);
    write_cmos(8'h02, 8'h34);
    write_cmos(8'h04, 8'h12);
    write_cmos(8'h06, 8'h05);
    write_cmos(8'h07, 8'h28);
    write_cmos(8'h08, 8'h08);
    write_cmos(8'h09, 8'h26);
    write_cmos(8'h0A, 8'h26);
    write_cmos(8'h0B, 8'h02);
    write_cmos(8'h32, 8'h20);

    @(negedge clk);
    rst_n = 1'b1;

    // The first update follows the short power-on UIP interval.
    wait(rtc_inst.rtc_second_update);
    @(posedge clk);
    #1;
    if(rtc_inst.rtc_second !== 8'h59)
        $fatal(1, "first RTC update produced %02x, expected 59",
            rtc_inst.rtc_second);

    // A complete second at 8 kHz contains about 8,000 system clocks. The
    // historical implementation accidentally took about 16,000 because it
    // used the full 799-tick second delay for the next UIP window as well.
    clocks_between_updates = 0;
    while(!rtc_inst.rtc_second_update) begin
        @(posedge clk);
        clocks_between_updates = clocks_between_updates + 1;
        if(clocks_between_updates > 9000)
            $fatal(1, "RTC second period exceeded 9,000 clocks");
    end
    @(posedge clk);
    #1;
    if(rtc_inst.rtc_second !== 8'h00 || rtc_inst.rtc_minute !== 8'h35)
        $fatal(1, "BCD rollover produced %02x:%02x, expected 35:00",
            rtc_inst.rtc_minute, rtc_inst.rtc_second);

    // UIP should be asserted only for the short four-tick update window.
    wait(rtc_inst.sec_state == 3'd1);
    uip_clocks = 0;
    while(rtc_inst.sec_state == 3'd1 || rtc_inst.sec_state == 3'd2) begin
        @(posedge clk);
        uip_clocks = uip_clocks + 1;
        if(uip_clocks > 100)
            $fatal(1, "RTC update-in-progress stayed high over 100 clocks");
    end

    $display("PASS: RTC second period=%0d clocks, UIP=%0d clocks",
        clocks_between_updates, uip_clocks);
    $finish;
end

initial begin
    #300000;
    $fatal(1, "RTC regression timed out");
end

endmodule
