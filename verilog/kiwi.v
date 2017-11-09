//////////////////////////////////////////////////////////////////////////
// Homemade GPS Receiver
// Copyright (C) 2013 Andrew Holme
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// http://www.holmea.demon.co.uk/GPS/Main.htm
//////////////////////////////////////////////////////////////////////////


// Copyright (c) 2014 John Seamons, ZL/KF6VO

`default_nettype none

`include "kiwi.vh"

module KiwiSDR (

    output wire	ADC_CLKEN,

    input  wire IF_SGN,
    input  wire IF_MAG,
    input  wire GPS_TCXO,

    input  wire	BBB_SCLK,
    input  wire [1:0] BBB_CS_N,
    input  wire BBB_MOSI,
    output wire BBB_MISO,

    output wire G030,
    output wire G031,
    input  wire G116,
    output wire G117,
    output wire G015,		// ctrl[CTRL_INTERRUPT]
    output wire G014,		// inside pin row
    
    output wire P826,		// outside pin row
    output wire P819,
    output wire P817,
    output wire P818,		// outside pin row
    output wire P815,
    output wire P816,		// outside pin row
    output wire P813,
    output wire P814,		// outside pin row
    output wire P811,
    output wire P812,		// outside pin row

    output wire EWP
    );
    
    
    //////////////////////////////////////////////////////////////////////////
    // debug
    
    // P9: 25 23 21 19 17 15 13 11 09 07 05 03 01
    //        b3          b2 b1 b0
    //
    // P9: 26 24 22 20 18 16 14 12 10 08 06 04 02
    //     b4
    
    wire [4:0] P9;
    
    assign G014 = P9[4];    // P9-26
    assign G117 = P9[3];    // P9-23
    assign G116 = P9[2];    // P9-15
    assign G031 = P9[1];    // P9-13
    assign G030 = P9[0];    // P9-11

    // P8: 25 23 21 19 17 15 13 11 09 07 05 03 01
    //              b8 b7 b6 b5 b4
    //
    // P8: 26 24 22 20 18 16 14 12 10 08 06 04 02
    //     b9          b3 b2 b1 b0
    
    wire [9:0] P8;
    
    assign P826 = P8[9];
    assign P819 = P8[8];
    assign P817 = P8[7];
    assign P815 = P8[6];
    assign P813 = P8[5];
    assign P811 = P8[4];
    assign P818 = P8[3];
    assign P816 = P8[2];
    assign P814 = P8[1];
    assign P812 = P8[0];

    
    //////////////////////////////////////////////////////////////////////////
    // clocks

    wire gps_clk, cpu_clk;
    
	localparam CLOCK_ID = 4'd0;

	assign ADC_CLKEN = 1'b0;

    IBUFG tcxo_ibufg(.I(GPS_TCXO), .O(gps_clk));		// 16.368 MHz TCXO
    assign cpu_clk = gps_clk;


    wire  [2:1] rst;

	wire [15:0] op;
    wire [31:0] nos, tos;
    reg  [15:0] par;
    wire [1:0]  ser;
	assign ser[1] = 1'b0;
    wire        rdBit, rdBit2, rdReg, rdReg2, wrReg, wrReg2, wrEvt, wrEvt2;

    wire        boot_done, host_srq, mem_rd, gps_rd;
    wire [15:0] host_dout, mem_dout, gps_dout;
    
    
    //////////////////////////////////////////////////////////////////////////
    // global control & status registers

    reg [15:0] ctrl;
    
    always @ (posedge cpu_clk)
    begin
        if (wrReg2 && op[SET_CTRL]) ctrl <= tos[15:0];
    end

	assign EWP = ctrl[CTRL_EEPROM_WP];
	assign G015 = ctrl[CTRL_INTERRUPT];
	
	// keep Vivado from complaining about unused inputs and outputs
	assign P9[0] = ctrl[CTRL_UNUSED_OUT];
	assign P9[1] = ctrl[CTRL_UNUSED_OUT];
	assign P9[3] = ctrl[CTRL_UNUSED_OUT];
	assign P9[4] = ctrl[CTRL_UNUSED_OUT];

	assign P8[0] = ctrl[CTRL_UNUSED_OUT];
	assign P8[1] = ctrl[CTRL_UNUSED_OUT];
	assign P8[2] = ctrl[CTRL_UNUSED_OUT];
	assign P8[3] = ctrl[CTRL_UNUSED_OUT];
	assign P8[4] = ctrl[CTRL_UNUSED_OUT];
	assign P8[5] = ctrl[CTRL_UNUSED_OUT];
	assign P8[6] = ctrl[CTRL_UNUSED_OUT];
	assign P8[7] = ctrl[CTRL_UNUSED_OUT];
	assign P8[8] = ctrl[CTRL_UNUSED_OUT];
	assign P8[9] = ctrl[CTRL_UNUSED_OUT];
	
	wire unused_inputs = IF_MAG | P9[2];
	
    wire [15:0] status;
    assign status[15:0] = { 3'b0, unused_inputs, FPGA_VER, CLOCK_ID, FPGA_ID };


    //////////////////////////////////////////////////////////////////////////
    // CPU parallel port input mux
	
wire [31:0] wcnt;

    always @*
`ifdef USE_CPU_CTR
		if (rdReg && op[GET_CPU_CTR0]) par = { cpu_ctr[1][ 7 -:8], cpu_ctr[0][ 7 -:8] }; else
		if (rdReg && op[GET_CPU_CTR1]) par = { cpu_ctr[1][15 -:8], cpu_ctr[0][15 -:8] }; else
		if (rdReg && op[GET_CPU_CTR2]) par = { cpu_ctr[1][23 -:8], cpu_ctr[0][23 -:8] }; else
		if (rdReg && op[GET_CPU_CTR3]) par = { cpu_ctr[1][31 -:8], cpu_ctr[0][31 -:8] }; else
`endif

		if (rdReg && op[GET_STATUS]) par = status; else
		par = host_dout;
	

    //////////////////////////////////////////////////////////////////////////
    // host SPI interface

    HOST host (
        .hb_clk		(gps_clk),
        .rst		(rst),
        .spi_sclk   (BBB_SCLK),
        .spi_cs		(~BBB_CS_N),
        .spi_mosi   (BBB_MOSI),
        .spi_miso   (BBB_MISO),
        .host_srq   (host_srq),
        
        .gps_rd 	(gps_rd),
        .gps_dout	(gps_dout),

        .host_dout  (host_dout),
        .mem_rd     (mem_rd),
        .mem_dout   (mem_dout),
        .boot_done  (boot_done),

        .tos        (tos),
        .op         (op),
        .rdReg      (rdReg),
        .wrReg      (wrReg),
        .wrEvt      (wrEvt)
        );


    //////////////////////////////////////////////////////////////////////////
    // CPU cycle counters

`ifdef USE_CPU_CTR
    reg cpu_ctr_ena;
    wire [31:0] cpu_ctr[1:0];
    wire sclr = wrEvt && op[CPU_CTR_CLR];
    
	ip_acc_u32b cpu_ctr0 (.clk(cpu_clk), .sclr(sclr), .b(1), .q(cpu_ctr[0]));
	ip_acc_u32b cpu_ctr1 (.clk(cpu_clk), .sclr(sclr), .b({{31{1'b0}}, cpu_ctr_ena}), .q(cpu_ctr[1]));

	always @ (posedge cpu_clk)
	begin
		if (wrEvt && op[CPU_CTR_ENA]) cpu_ctr_ena <= 1;
		if (wrEvt && op[CPU_CTR_DIS]) cpu_ctr_ena <= 0;
	end
`endif

    CPU cpu (
        .clk        (cpu_clk),
        .rst        (rst),
        
        .par        (par),
        .ser        (ser),
        .mem_rd     (mem_rd),
        .mem_dout   (mem_dout),
        .boot_done  (boot_done),
        
        .tos        (tos),
        .op         (op),
        .rdBit      (rdBit),
        .rdBit2     (rdBit2),
        .rdReg      (rdReg),
        .rdReg2     (rdReg2),
        .wrReg      (wrReg),
        .wrReg2     (wrReg2),
        .wrEvt      (wrEvt),
        .wrEvt2     (wrEvt2)
        );


`ifdef DEF_GPS_CHANS
    GPS gps (
        .clk        (gps_clk),
        .host_srq   (host_srq),

        .I_data		(IF_SGN),
        .gps_rd 	(gps_rd),
        .gps_dout	(gps_dout),
        
        .ser		(ser[0]),        
        .tos		(tos),			// fixme: cpu_clk?
        .op			(op),        
        .rdBit      (rdBit),
        .rdReg      (rdReg),
        .wrReg      (wrReg),
        .wrEvt      (wrEvt)
        );
`else

	// if no GPS configured, still need to capture host_srq in the same way as GPS.
	assign ser[0] = srq_out;
	reg srq_noted, srq_out;
	
    always @ (posedge cpu_clk)
    begin
        if (rdReg && op[GET_SRQ]) srq_noted <= host_srq;
        else				     srq_noted <= host_srq | srq_noted;
        if (rdReg && op[GET_SRQ]) srq_out <= srq_noted;
    end
`endif

endmodule
