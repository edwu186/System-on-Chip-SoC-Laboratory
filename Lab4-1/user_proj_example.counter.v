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
