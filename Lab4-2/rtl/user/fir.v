`timescale 1ns / 1ps

module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
    output  wire                     awready,
    output  wire                     wready, 
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,

    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  wire                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,  

    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  wire                     ss_tready, 

    input   wire                     sm_tready, 
    output  wire                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  wire                     sm_tlast, 
    
    // bram for tap RAM
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,  
    output  wire [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do, 

    // bram for data RAM
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);
    
    localparam IDLE = 2'b00;
    localparam CAL  = 2'b01;
    localparam DONE = 2'b10;
    
    reg [1:0] state, next_state;
    reg ap_start, ap_idle, ap_done;
    
    reg [pADDR_WIDTH-1:0] data_length;
    reg [pADDR_WIDTH-1:0] tlast_cnt; 
    
    //-----------------------------------AXI Lite Signal-------------------------------------
    reg awready_reg;
    reg wready_reg;
    reg arready_reg;
    reg rvalid_reg;
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            awready_reg <= 0;
            wready_reg <= 0;
            arready_reg <= 0;
            rvalid_reg <= 0;
        end else begin
            awready_reg <= (state == IDLE) ? 1 : 0;
            wready_reg <= (state == IDLE) ? 1 : 0;
            arready_reg <= (arvalid) ? 1 : 0;
            rvalid_reg <= (arvalid && arready) ? 1 : 0;
        end
    end
    
    assign awready = awready_reg;
    assign wready = wready_reg;
    assign arready = arready_reg;
    assign rvalid = rvalid_reg;
    
    //--------------------------------FSM & Configuration Register Signal ---------------------- 
    always @(*) begin
        case(state)
            IDLE : begin
                ap_idle = 1;
                ap_start = 0;
                ap_done = 0;
                next_state = (awaddr == 12'h00 && wdata[0] == 1 && ap_idle) ? CAL : IDLE;
            end
            CAL : begin
                ap_idle = sm_tlast; // when last data is transferred
                ap_start = (tlast_cnt != data_length) ? 1 : 0;
                ap_done = 0;
                next_state = (sm_tvalid && sm_tlast) ? DONE : CAL;
            end
            DONE : begin
                ap_idle = sm_tlast; // proccessing last data
                ap_start = 0;
                ap_done = (sm_tlast) ? 0 : 1; // wait until last data is transferred
                next_state = (araddr == 12'h00 && arvalid && rvalid) ? IDLE : DONE;
            end
            default : begin
                ap_idle = 0;
                ap_start = 0;
                ap_done = 0;
                next_state = IDLE;
            end
        endcase
    end
    
     always @(posedge axis_clk or negedge axis_rst_n) begin
            if (!axis_rst_n)
                state <= IDLE;
            else
                state <= next_state;
    end
    
    //------- --------------------------Tap_Do Output Select---------------------------------------------
    // Input 0x00 :bit 0: ap_start, bit 1: ap_done, bit 2: ap_idle
    // Input 0x10-14 : data length
    // Input 0x20-FF : tap parameters
    reg [pDATA_WIDTH-1:0] rdata_reg;
    always @(*) begin
        if (araddr == 12'h00) begin
            rdata_reg = (ap_start != 1) ? ({{{29'b0,ap_idle},ap_done},ap_start}) : 32'b0; // if read in the middle of CAL, ap_idel = 0;
        end
        else if (araddr == 12'h10) rdata_reg = data_length;
        else if (araddr >= 12'h20) rdata_reg = tap_Do;
        else rdata_reg = 0;
    end
    assign rdata = rdata_reg;
    
    // Store data_length value 
    wire [pADDR_WIDTH-1:0] data_length_tmp;
    assign data_length_tmp = (awaddr == 12'h10) ? wdata : data_length;
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
            if (!axis_rst_n)
                data_length <= 0;
            else
                data_length <= data_length_tmp;
    end
    
    //-----------------------------tap_RAM signal------------------------------------------
    assign tap_EN = (state == IDLE || state == CAL) ? 4'b1111 : 4'b0000;
    assign tap_WE = (state == IDLE) ? ((awvalid && wvalid) ? 4'b1111 : 4'b0000) : 4'b0000;
    assign tap_Di = wdata;
    assign tap_A = (state == IDLE) ? ((awvalid && wvalid ) ? (awaddr-12'h20) : tap_A_r) : tap_A_r; // if read use
    
    
    //-----------------------------data_RAM signal---------------------------------------------
    assign data_EN = 1;
    assign data_WE =  (ss_tready || data_addr != 6'd44) ? 4'b1111 : 4'b0000;
    assign data_Di = (state == IDLE && data_addr != 6'd44)? 0 : ss_tdata; //initialize first 11 data with 0
    assign data_A = (state == IDLE && data_addr != 6'd44) ? data_addr : data_A_tmp;
    
    wire [(pADDR_WIDTH-1):0] next_data_addr;
    reg  [(pADDR_WIDTH-1):0] data_addr;
        
    assign next_data_addr = (data_addr == 6'd44)? data_addr : data_addr + 6'd4;   
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n)
            data_addr <= -6'd4;
        else
            data_addr <= next_data_addr;
    end
    
    
    //---------------------------------AXI Stream Signal-------------------------------------------------------
    assign ss_tready = (state == CAL && data_addr == 6'd44 && k == 4'd0)? 1'b1 : 1'b0;
    assign sm_tvalid = (state == CAL && y_cnt == 5'd0)? 1'b1 : 1'b0;
    assign sm_tdata  = y;
    assign sm_tlast  = (state == CAL && tlast_cnt_tmp == data_length) ? 1'b1 : 1'b0;
    
    //---------------------Count to the cycle Y need to be output-------------------------------- 
    reg  [4:0] y_cnt;
    wire [4:0] y_cnt_tmp;
    
    assign y_cnt_tmp = (y_cnt != 6'd10 && ap_idle == 0)? y_cnt + 1'b1 : 5'd0;
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n || ap_idle == 1)
            y_cnt <= -5'd15; //the first y is come out at y_cnt = 0, 14 cycle needed
        else
            y_cnt <= y_cnt_tmp;
    end
    
    //---------------------Count to the data length for sm_tlast ------------------
    wire [pADDR_WIDTH-1:0] tlast_cnt_tmp;
    
    assign tlast_cnt_tmp = (sm_tvalid == 1'b1)? tlast_cnt + 1'b1 : tlast_cnt;
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n) 
            tlast_cnt <= 11'd0;
        else
            tlast_cnt <= tlast_cnt_tmp;
    end
    
    //---------------------- ----Generate tap RAM address ----------------------
    wire [pADDR_WIDTH-1:0] tap_A_r;
    reg  [3:0] k;
    wire [3:0] k_tmp;
    
    assign k_tmp = (k != 4'd10)? k + 4'd1 : 4'd0;
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n || state == IDLE)
            k <= 4'd10;
        else
            k <= k_tmp;
    end
    
    assign tap_A_r = (ap_idle == 0) ? 4 * k : (araddr-12'h20);
    
    //---------------------------Generate data RAM address ------------------
    reg [3:0] x_cnt;
    reg [3:0] x_cnt_tmp;
    
    always @* begin
        if (ap_idle == 0) begin
            if (k == 4'd10)
                if (x_cnt != 4'd10)
                    x_cnt_tmp = x_cnt + 1'b1;
                else
                    x_cnt_tmp =  4'd0;
            else
                x_cnt_tmp = x_cnt;
        end
        else
            x_cnt_tmp = 4'd0;
    end
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n)
            x_cnt <= 4'd0;
        else
            x_cnt <= x_cnt_tmp;
    end
      
    wire [pADDR_WIDTH-1:0] data_A_tmp;
    
    assign data_A_tmp = (k <= x_cnt)? 4 * (x_cnt - k) : 4 * (11 + x_cnt - k); 
    
    
    
    //---------------------Store the first coef value------------------------
    // Handle the situation when begin CAL state, write ap_start into tap_ram, the first tap_do is not coef value
    reg signed [31:0] first_coef;  // change need no need for ff
    wire signed [31:0] first_coef_tmp;
    
    assign first_coef_tmp = (awaddr == 12'h20) ? wdata : first_coef;
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
            if (!axis_rst_n)
                first_coef <= 0;
            else
                first_coef <= first_coef_tmp;
    end
    
    
    //-------------------MUX to select first_coef or tap_Do-------------------------
    wire [(pDATA_WIDTH-1):0] h_sel;
    reg  mux_tap_sel;
        
    always @* begin
        if (awready == 1)
            mux_tap_sel = 1;
        else
            mux_tap_sel = 0;
    end
    
    assign h_sel = (mux_tap_sel)? first_coef : tap_Do;
    
    
    //---------------------------Store the ss_tdata-------------------------------
    // Handle the situation when data_Do is need earlier, since data_Do is one cycle after data_Di
    // first x is this stored value
    reg  [(pDATA_WIDTH-1):0] data_ff;
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n) begin
            data_ff <= 32'd0;
        end
        else begin
            data_ff <= ss_tdata;
        end
    end
    
    //-------------------MUX to select first x or data_RAM -------------
    wire [(pDATA_WIDTH-1):0] x_sel;
    reg  mux_data_sel;
    
    always @* begin
        if (k == 4'd0)
            mux_data_sel = 1;
        else
            mux_data_sel = 0;
    end
    
    assign x_sel = (mux_data_sel)? data_ff : data_Do;
    
    
    //--------------------Pipeline Operation for MUL and ADD ------------------------------
    reg  [(pDATA_WIDTH-1):0] h;
    wire [(pDATA_WIDTH-1):0] h_tmp;
    
    reg  [(pDATA_WIDTH-1):0] x;
    wire [(pDATA_WIDTH-1):0] x_tmp;
     
    reg  [(pDATA_WIDTH-1):0] m; 
    wire [(pDATA_WIDTH-1):0] m_tmp;
    
    reg  [(pDATA_WIDTH-1):0] y;
    wire [(pDATA_WIDTH-1):0] y_tmp; 
    
    always @(posedge axis_clk or negedge axis_rst_n) begin
        if (!axis_rst_n || ap_idle == 1) begin
            h <= 32'd0;
            x <= 32'd0;
            m <= 32'd0;
            y <= 32'd0;
        end
        else begin
            h <= h_tmp;
            x <= x_tmp;
            m <= m_tmp;
            if (y_cnt == 0)
                y <= 0;
            else
                y <= y_tmp;
        end
    end
    
    assign h_tmp = h_sel;          
    assign x_tmp = x_sel;           
    assign m_tmp = h * x;
    assign y_tmp = m + y;         
endmodule