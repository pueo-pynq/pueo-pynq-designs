`timescale 1ns / 1ps
`include "interfaces.vh"

// Pre-trigger filter chain.
// 1) Shannon-Whitaker low pass filter
// 2) Two Biquads in serial (to be used as notches)
// 3) AGC and 12->5 bit conversion
module trigger_chain_wrapper #(parameter AGC_TIMESCALE_REDUCTION = 4)(  


        input wb_clk_i,
        input wb_rst_i,

        // Wishbone stuff for writing in coefficients to the biquads
        `TARGET_NAMED_PORTS_WB_IF( wb_bq_ , 8, 32 ), // Address width, data width. 

        // Wishbone stuff for writing to the AGC
        `TARGET_NAMED_PORTS_WB_IF( wb_agc_controller_ , 8, 32 ), // Address width, data width.
        
        // Control to capture the output to the RAM buffer
        input reset_i, 
        input aclk,
        input [95:0] dat_i,
        
        output [39:0] dat_o
    );

    // QUALITY OF LIFE FUNCTIONS

    // UNPACK is 128 -> 96
    function [95:0] unpack;
        input [127:0] data_in;
        integer i;
        begin
            for (i=0;i<8;i=i+1) begin
                unpack[12*i +: 12] = data_in[(16*i+4) +: 12];
            end
        end
    endfunction

    // PACK is 96 -> 128
    function [127:0] pack;
        input [95:0] data_in;
        integer i;
        begin
            for (i=0;i<8;i=i+1) begin
                pack[(16*i+4) +: 12] = data_in[12*i +: 12];
                pack[(16*i) +: 4] = {4{1'b0}};
            end
        end
    endfunction    


    task do_write_to_agc; 
        input [21:0] in_addr;
        input [31:0] in_data;
        begin
            address_agc = in_addr;
            data_agc_o = `DLYFF in_data;
            use_agc_wb = 1'b1;
            wr_agc_wb = 1'b1;
        end
    endtask

    task finish_write_cycle_agc; 
        begin
            use_agc_wb = 1'b0;
            wr_agc_wb = 1'b0;
            address_agc = 22'h0;
            data_agc_o = 32'h0;
        end
    endtask

    task do_read_req_agc; 
        input [21:0] in_addr;
        begin
            address_agc = in_addr;
            use_agc_wb = 1'b1;
            wr_agc_wb = 1'b0;
        end
    endtask

    task finish_read_cycle_agc; 
        output [31:0] out_data;
        begin
            out_data = wb_agc_dat_i;
            use_agc_wb = 1'b0;
            wr_agc_wb = 1'b0;
            address_agc = 22'h0;
        end
    endtask

    `define ADDR_MATCH( addr, val, mask ) ( ( addr & mask ) == (val & mask) )
    localparam [7:0] AGC_MASK = {8{1'b1}}; // May be unused
    // localparam NBITS_KP = 32;
    // localparam NFRAC_KP = 10;

    // WB interface to actual AGC module
    `DEFINE_WB_IF( wb_agc_module_ , 8, 32);

    // DOWNSTREAM CONTROL ///////////////////////////////////////////////////
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [21:0] address_agc = {8{1'b0}};

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] data_agc_o = {32{1'b0}};
    
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg use_agc_wb = 0; 
    
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg wr_agc_wb = 0; 

    assign wb_agc_module_dat_o = data_agc_o;
    assign wb_agc_module_adr_o = address_agc;
    assign wb_agc_module_cyc_o = use_agc_wb;
    assign wb_agc_module_stb_o = use_agc_wb;
    assign wb_agc_module_we_o = wr_agc_wb; // Tie this in too if only ever writing
    assign wb_agc_module_sel_o = {4{use_agc_wb}};

    // UPSTREAM RECEIVER ///////////////////////////////////////////////////
    // WB interface to the AGC control loop (in this module)
    // //  Top interface target (S)        Connection interface (M)
    assign wb_ack_o = (state == ACK);
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;
    assign wb_dat_o = response_reg;

   
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] response_reg = 32'h0; // Pass back AGC information

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [7:0][31:0] agc_info_reg = {8{32{1'b0}}}; // Store of downstream AGC info

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [16:0] agc_control_scale_delta = STARTING_SCALE_DELTA; // change amount 
    
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [15:0] agc_control_offset_delta = STARTING_OFFSET_DELTA; // change amount 

    (* CUSTOM_CC_SRC = WBCLKTYPE *) // Store the to-be updated agcs here
    reg [NBEAMS-1:0][16:0] agc_recalculated_scale_regs = {NBEAMS{`STARTSCALE}};
    
    (* CUSTOM_CC_SRC = WBCLKTYPE *) // Store the to-be updated agcs here
    reg [NBEAMS-1:0][15:0] agc_recalculated_offset_regs = {NBEAMS{`STARTOFFSET}};

    // (* CUSTOM_CC_SRC = WBCLKTYPE *) // Store the agcs here
    // reg [NBEAMS-1:0][17:0] agc_regs = {NBEAMS{`STARTTHRESH}};

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] agc_module_response = 32'h0; 

    // Upstream State machine control
    localparam FSM_BITS = 2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] WRITE = 1;
    localparam [FSM_BITS-1:0] READ = 2;
    localparam [FSM_BITS-1:0] ACK = 3;
    reg [FSM_BITS-1:0] state = IDLE;   

    //////////////////////////////////////////////////////////
    //////        Wishbone FSM For Upstream Comms       //////
    //////////////////////////////////////////////////////////
    always @(posedge wb_clk_i) begin
        
        // Determine what we are doing this cycle
        case (state)
            IDLE: if (wb_agc_controller_cyc_i && wb_agc_controller_stb_i) begin
                if (wb_agc_controller_we_i) state <= WRITE;
                else state <= READ;
            end
            WRITE: state <= ACK;
            READ: state <= ACK;
            ACK: state <= IDLE;
            default: state <= IDLE; // Should never go here
        endcase
        
        // If reading, load the response in
        if (state == READ) begin
            // If bit [4] is 1, return from control loop info
            // Else, bit [4] is 0, return from AGC module info
            if(wb_agc_controller_adr_i[4]) begin 
                case (bw_agc_controller_adr_i[3:0])
                    0: response_reg <= {{(32-17){1'b0}}, agc_control_scale_delta};
                    1: response_reg <= {{(32-16){agc_control_offset_delta[15]}}, agc_control_offset_delta};
                endcase
                // response_reg <= agc_info_reg[wb_agc_controller_adr_i[3:0]];
            end else begin
                response_reg <= agc_info_reg[wb_agc_controller_adr_i[3:0]];
            end
        end
        // If writing to a threshold, put it in the appropriate register
        if (state == WRITE) begin
            // NO CURRENT NEED FOR WRITING, CAN IMPLEMENT LATER

            // if (wb_adr_i[8]) begin // The 8th bit is used to indicate a threshold write
            //     if (wb_sel_i[0]) threshold_regs[wb_adr_i[7:0]][7:0] <= wb_dat_i[7:0];
            //     if (wb_sel_i[1]) threshold_regs[wb_adr_i[7:0]][15:8] <= wb_dat_i[15:8];
            //     if (wb_sel_i[2]) threshold_regs[wb_adr_i[7:0]][17:16] <= wb_dat_i[17:16];
            // end             
        end
    end





    wire [95:0] data_stage_connection [1:0]; // In 12 bits since that's what the LPF works in

    // Low pass filter

    shannon_whitaker_lpfull_v2 u_lpf (  .clk_i(aclk),
                                        .in_i(dat_i),
                                        .out_o(data_stage_connection[0]));

    // Biquads

    biquad8_x2_wrapper u_biquadx2(
        .wb_clk_i(wb_clk_i),
        .wb_rst_i(wb_rst_i),        
        `CONNECT_WBS_IFS( wb_ , wb_bq_ ),
        .reset_BQ_i(reset_i),
        .aclk(aclk),
        .dat_i(data_stage_connection[0]),
        .dat_o(data_stage_connection[1])
    );

    agc_wrapper #(.TIMESCALE_REDUCTION(AGC_TIMESCALE_REDUCTION))
     u_agc_wrapper(
        .wb_clk_i(wb_clk_i),
        .wb_rst_i(wb_rst_i),        
        `CONNECT_WBS_IFM( wb_ , wb_agc_module_ ),
        .aclk(aclk),
        .aresetn(reset_i),
        .dat_i(data_stage_connection[1]),
        .dat_o(dat_o)
    );


endmodule
