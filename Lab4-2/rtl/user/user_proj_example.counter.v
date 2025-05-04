// SPDX-FileCopyrightText: 2020 Efabless Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// SPDX-License-Identifier: Apache-2.0

`default_nettype wire
/*
 *-------------------------------------------------------------
 *
 * user_proj_example
 *
 * This is an example of a (trivially simple) user project,
 * showing how the user project can connect to the logic
 * analyzer, the wishbone bus, and the I/O pads.
 *
 * This project generates an integer count, which is output
 * on the user area GPIO pads (digital output only).  The
 * wishbone connection allows the project to be controlled
 * (start and stop) from the management SoC program.
 *
 * See the testbenches in directory "mprj_counter" for the
 * example programs that drive this user project.  The three
 * testbenches are "io_ports", "la_test1", and "la_test2".
 *
 *-------------------------------------------------------------
 */
`define MPRJ_IO_PADS_1 19	/* number of user GPIO pads on user1 side */
`define MPRJ_IO_PADS_2 19	/* number of user GPIO pads on user2 side */
`define MPRJ_IO_PADS (`MPRJ_IO_PADS_1 + `MPRJ_IO_PADS_2)


module user_proj_example #(
    parameter BITS = 32,
    parameter DELAYS=10
)(
`ifdef USE_POWER_PINS
    inout vccd1,	// User area 1 1.8V supply
    inout vssd1,	// User area 1 digital ground
`endif

    // Wishbone Slave ports (WB MI A)
    input wb_clk_i,
    input wb_rst_i,
    input wbs_stb_i,
    input wbs_cyc_i,
    input wbs_we_i,
    input [3:0] wbs_sel_i,
    input [31:0] wbs_dat_i,
    input [31:0] wbs_adr_i,
    output reg wbs_ack_o,
    output reg [31:0] wbs_dat_o,

    // Logic Analyzer Signals
    input  [127:0] la_data_in,
    output [127:0] la_data_out,
    input  [127:0] la_oenb,

    // IOs
    input  [`MPRJ_IO_PADS-1:0] io_in,
    output [`MPRJ_IO_PADS-1:0] io_out,
    output [`MPRJ_IO_PADS-1:0] io_oeb,

    // IRQ
    output [2:0] irq
);

    //  AXI-Lite
    wire        awready;
    wire        wready; 
    wire        awvalid;
    wire [11:0] awaddr; 
    wire        wvalid; 
    wire [31:0] wdata;  
    wire        arready;
    wire        rready;
    wire        arvalid;
    wire [11:0] araddr;
    wire        rvalid;
    wire [31:0] rdata;
    
    //  AXI-Stream
    wire        ss_tvalid; 
    wire [31:0] ss_tdata;
    wire        ss_tlast;
    wire        ss_tready; 
    wire        sm_tready;
    wire        sm_tvalid;
    wire [31:0] sm_tdata;
    wire        sm_tlast;

    // bram for tap RAM
    wire [3:0]  tap_WE;
    wire        tap_EN;
    wire [31:0] tap_Di;
    wire [11:0] tap_A;
    wire [31:0] tap_Do;

    // bram for data RAM
    wire [3:0]  data_WE;
    wire        data_EN;
    wire [31:0] data_Di;
    wire [11:0] data_A;
    wire [31:0] data_Do;

    // clk && reset 
    wire        axis_clk;
    wire        axis_rst_n;

    // WB response signals
    wire        wbs_ack_o_fir;
    wire [31:0] wbs_dat_o_fir;
    wire        wbs_ack_o_exem_fir;
    wire [31:0] wbs_dat_o_exem_fir;

    always @(*) begin
        if (wbs_cyc_i && wbs_stb_i) begin
            if (wbs_adr_i[31:16] == 16'h380) begin
                 wbs_ack_o = wbs_ack_o_exem_fir;
                 wbs_dat_o = wbs_dat_o_exem_fir;
            end else if (wbs_adr_i[31:16] == 16'h300) begin
                 wbs_ack_o = wbs_ack_o_fir;
                 wbs_dat_o = wbs_dat_o_fir;
            end
        end else begin
            wbs_ack_o = 0;
            wbs_dat_o = 0;
        end
    end

    wb_to_exmem_fir userbram (
        .wb_clk_i(wb_clk_i),
        .wb_rst_i(wb_rst_i),
        .wbs_cyc_i(wbs_cyc_i),
        .wbs_stb_i(wbs_stb_i),
        .wbs_we_i(wbs_we_i),
        .wbs_sel_i(wbs_sel_i),
        .wbs_dat_i(wbs_dat_i),
        .wbs_adr_i(wbs_adr_i),
        .wbs_ack_o(wbs_ack_o_exem_fir),
        .wbs_dat_o(wbs_dat_o_exem_fir)
    );  

    wb_to_axi verilog_fir (
        .wb_clk_i(wb_clk_i),
        .wb_rst_i(wb_rst_i),
        .wbs_cyc_i(wbs_cyc_i),
        .wbs_stb_i(wbs_stb_i),
        .wbs_we_i(wbs_we_i),
        .wbs_sel_i(wbs_sel_i),
        .wbs_dat_i(wbs_dat_i),
        .wbs_adr_i(wbs_adr_i),
        .wbs_ack_o(wbs_ack_o_fir),
        .wbs_dat_o(wbs_dat_o_fir),

        // AXI-Lite
        .awready(awready),
        .wready(wready),
        .awvalid(awvalid),
        .awaddr(awaddr),
        .wvalid(wvalid),
        .wdata(wdata),

        .arready(arready),
        .rready(rready),
        .arvalid(arvalid),
        .araddr(araddr),
        .rvalid(rvalid),
        .rdata(rdata),

        // AXI-Stream
        .ss_tvalid(ss_tvalid), 
        .ss_tdata(ss_tdata), 
        .ss_tlast(ss_tlast), 
        .ss_tready(ss_tready), 

        .sm_tready(sm_tready), 
        .sm_tvalid(sm_tvalid), 
        .sm_tdata(sm_tdata), 
        .sm_tlast(sm_tlast)
    );

    fir to_fir(
        // AXI-Lite
        .awready(awready),
        .wready(wready),
        .awvalid(awvalid),
        .awaddr(awaddr),
        .wvalid(wvalid),
        .wdata(wdata),

        .arready(arready),
        .rready(rready),
        .arvalid(arvalid),
        .araddr(araddr),
        .rvalid(rvalid),
        .rdata(rdata),

        // AXI-Stream
        .ss_tvalid(ss_tvalid), 
        .ss_tdata(ss_tdata), 
        .ss_tlast(ss_tlast), 
        .ss_tready(ss_tready), 

        .sm_tready(sm_tready), 
        .sm_tvalid(sm_tvalid), 
        .sm_tdata(sm_tdata), 
        .sm_tlast(sm_tlast),
 
        .axis_clk(wb_clk_i),
        .axis_rst_n(!wb_rst_i)
    );

    bram11 data_ram (
        .clk(wb_clk_i),
        .we(data_WE[0]),
        .re(data_EN),
        .waddr(data_A),
        .raddr(data_A),
        .wdi(data_Di),
        .rdo(data_Do)
    );

    bram11 tap_ram (
        .clk(wb_clk_i),
        .we(tap_WE[0]),
        .re(tap_EN),
        .waddr(tap_A),
        .raddr(tap_A),
        .wdi(tap_Di),
        .rdo(tap_Do)
    );

endmodule

module wb_to_axi (
    //WB
    input wb_clk_i,
    input wb_rst_i,
    input wbs_stb_i,
    input wbs_cyc_i,
    input wbs_we_i,
    input [3:0] wbs_sel_i,
    input [31:0] wbs_dat_i,
    input [31:0] wbs_adr_i,
    output wbs_ack_o,
    output [31:0] wbs_dat_o,

    // AXI-LITE
    input         awready,
    input         wready,
    output        awvalid,
    output [11:0] awaddr, 
    output        wvalid, 
    output [31:0] wdata,

    input         arready,
    output        rready,
    output        arvalid,
    output [11:0] araddr,
    input         rvalid,
    input  [31:0] rdata,
    
    //  AXI-Stream
    output        ss_tvalid, 
    output [31:0] ss_tdata,
    output        ss_tlast,
    input         ss_tready, 
    output        sm_tready,
    input         sm_tvalid,
    input  [31:0] sm_tdata,
    input         sm_tlast  
);

    wire fir_valid;
    wire fir_tap;
    wire fir_ctrl;
    wire fir_length;
    wire fir_x_in;
    wire fir_y_out;

    assign fir_valid = wbs_cyc_i && wbs_stb_i && ((wbs_adr_i[31:16] == 16'h300) ? 1'b1 : 1'b0);
    assign fir_ctrl = (fir_valid && wbs_adr_i[7:0] == 8'h00)? 1'b1 : 1'b0;
    assign fir_length = (fir_valid && wbs_adr_i[7:0] >= 8'h10 && wbs_adr_i[7:0] <= 8'h13)? 1'b1 : 1'b0;
    assign fir_tap = (fir_valid && wbs_adr_i[7:0] >= 8'h40 && wbs_adr_i[7:0] <= 8'h7F)? 1'b1 : 1'b0;
    assign fir_x_in = (fir_valid && wbs_adr_i[7:0] >= 8'h80 && wbs_adr_i[7:0] <= 8'h83)? 1'b1 : 1'b0;
    assign fir_y_out = (fir_valid && wbs_adr_i[7:0] >= 8'h84 && wbs_adr_i[7:0] <= 8'h87)? 1'b1 : 1'b0;

    //AXI Write
    assign awvalid = ((fir_ctrl || fir_tap || fir_length) && wbs_we_i) ? 1'b1 : 1'b0;
    assign awaddr = wbs_adr_i;
    assign wvalid = ((fir_ctrl || fir_tap || fir_length) && wbs_we_i) ? 1'b1 : 1'b0;
    assign wdata = wbs_dat_i;

    // AXI Read
    assign arvalid = (!wbs_we_i && fir_tap) ? 1'b1 : 1'b0;
    assign rready  = (!wbs_we_i && fir_tap) ? 1'b1 : 1'b0;
    assign araddr  = (!wbs_we_i && fir_tap ) ? wbs_adr_i : 0;

    // Stream in
    assign ss_tvalid = (wbs_we_i && fir_x_in) ? 1'b1 : 1'b0;
    assign ss_tdata  = (wbs_we_i && fir_x_in) ? wbs_dat_i : 0;
    assign ss_tlast  = (wbs_we_i && fir_x_in) ? 1'b1 : 1'b0;

    // Stream out
    assign sm_tready = (fir_y_out) ? 1'b0 : 1'b0;
    
    assign wbs_dat_o = (fir_ctrl || fir_tap || fir_length) ? rdata : (fir_y_out) ? sm_tdata : 0;
    assign wbs_ack_o = (awready && wready) ? 1'b1 :
        (rready && rvalid) ? 1'b1 :
        (ss_tvalid && ss_tready) ? 1'b1 :
        (sm_tvalid && sm_tready) ? 1'b1 : 1'b0;

endmodule


module wb_to_exmem_fir #(
    parameter BITS = 32,
    parameter DELAYS=10
)(
`ifdef USE_POWER_PINS
    inout vccd1,	// User area 1 1.8V supply
    inout vssd1,	// User area 1 digital ground
`endif

    // Wishbone Slave ports (WB MI A)
    input wb_clk_i,
    input wb_rst_i,
    input wbs_stb_i,
    input wbs_cyc_i,
    input wbs_we_i,
    input [3:0] wbs_sel_i,
    input [31:0] wbs_dat_i,
    input [31:0] wbs_adr_i,
    output wbs_ack_o,
    output [31:0] wbs_dat_o,

    // Logic Analyzer Signals
    input  [127:0] la_data_in,
    output [127:0] la_data_out,
    input  [127:0] la_oenb,

    // IOs
    input  [`MPRJ_IO_PADS-1:0] io_in,
    output [`MPRJ_IO_PADS-1:0] io_out,
    output [`MPRJ_IO_PADS-1:0] io_oeb,

    // IRQ
    output [2:0] irq
);
    wire clk;
    wire rst;

    // wire [`MPRJ_IO_PADS-1:0] io_in;
    // wire [`MPRJ_IO_PADS-1:0] io_out;
    // wire [`MPRJ_IO_PADS-1:0] io_oeb;

    wire ram_en; //bram enable input by master (valid)
    wire [3:0] ram_we; //bram write enable(byte)
    wire [31:0] ram_data_i; //bram data_in
    wire [31:0] ram_data_o; //bram data_out
    wire [31:0] ram_adr;    //address in bram

    reg ready; //outpyt by slave(READY)
    reg [3:0] count;
    
    // Wishbone Signals 
    assign clk = wb_clk_i;
    assign rst = wb_rst_i;

    assign ram_en = wbs_cyc_i && wbs_stb_i && ((wbs_adr_i[31:20] == 12'h380) ? 1'b1 : 1'b0);
    assign ram_we = ram_en ? ({4{wbs_we_i}} & wbs_sel_i) : 4'b0;
    assign wbs_ack_o = ready;

    assign ram_adr = ram_en ? wbs_adr_i : 32'b0;
    assign ram_data_i = ram_en ? wbs_dat_i : 32'b0;
    assign wbs_dat_o = ram_data_o;

    always @(posedge clk) begin
        if(rst) begin
            ready <= 1'b0;
            count <= 4'b0;
        end else if(ram_en) begin
            if(count == DELAYS) begin
                ready <= 1'b1;
                count <= 4'b0;
            end
            else begin
                ready <= 1'b0;
                count <= count + 1'b1;
            end
        end else begin
            ready <= 1'b0;
            count <= 4'b0;
        end
    end

    bram user_bram (
        .CLK(clk),
        .WE0(ram_we),
        .EN0(ram_en),
        .Di0(ram_data_i),
        .Do0(ram_data_o),
        .A0(ram_adr)
    );

endmodule

`default_nettype wire
