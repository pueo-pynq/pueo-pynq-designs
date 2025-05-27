`timescale 1ns / 1ps
`include "interfaces.vh"

`define DLYFF #0.1

module L1_trigger_wrapper #(parameter NBEAMS=2, parameter AGC_TIMESCALE_REDUCTION_BITS = 2,
                    parameter WBCLKTYPE = "PSCLK", parameter CLKTYPE = "ACLK",
                    parameter TRIGGER_CLOCKS=375000000,// at 375 MHz this will count for 1 s  
                    parameter HOLDOFF_CLOCKS=16,
                    parameter STARTING_TARGET=100,
                    parameter STARTING_KP=1)( 

        input wb_clk_i,
        input wb_rst_i,

        `TARGET_NAMED_PORTS_WB_IF( wb_ , 22, 32 ), // Address width, data width.
        input reset_i, 
        input aclk,
        input [7:0][95:0] dat_i,
        
        output [NBEAMS-1:0] trigger_o
    );

    `define ADDR_MATCH( addr, val, mask ) ( ( addr & mask ) == (val & mask) )
    localparam [9:0] THRESHOLD_MASK = {10{1'b1}};
    localparam NBITS_KP = 32;
    localparam NFRAC_KP = 10;

    // Pass commands not about trigger rate control loop down
    `DEFINE_WB_IF( L1_submodule_ , 22, 32);

    // //  Top interface target (S)        Connection interface (M)
    assign wb_ack_o = (wb_adr_i[14]) ? L1_submodule_ack_i : (state == ACK);
    assign wb_err_o = (wb_adr_i[14]) ? L1_submodule_err_i : 1'b0;
    assign wb_rty_o = (wb_adr_i[14]) ? L1_submodule_rty_i : 1'b0;
    assign wb_dat_o = (wb_adr_i[14]) ? L1_submodule_dat_i : response_reg;
    
    wire wb_control_loop_cyc_i;

    assign L1_submodule_cyc_o = wb_cyc_i && !wb_adr_i[14];
    assign wb_control_loop_cyc_i = wb_cyc_i && wb_adr_i[14];
    assign L1_submodule_stb_o = wb_stb_i;
    assign wb_control_loop_stb_o = wb_stb_i;
    assign L1_submodule_adr_o = wb_adr_i;
    assign wb_control_loop_adr_o = wb_adr_i;
    assign L1_submodule_dat_o = wb_dat_i;
    assign wb_control_loop_dat_o = wb_dat_i;
    assign L1_submodule_we_o = wb_we_i;
    assign wb_control_loop_we_o = wb_we_i;
    assign L1_submodule_sel_o = wb_sel_i;
    assign wb_control_loop_sel_o = wb_sel_i;


    // State machine control
    localparam FSM_BITS = 2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] WRITE = 1;
    localparam [FSM_BITS-1:0] READ = 2;
    localparam [FSM_BITS-1:0] ACK = 3;
    reg [FSM_BITS-1:0] state = IDLE;    

   
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] response_reg = 31'h0; // Pass back trigger count information

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] trigger_count_wb_reg; // Pass back # of triggers on WB

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] trigger_target_wb_reg = STARTING_TARGET; // The target number of triggers in the sample period

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] trigger_threshold_wb_reg; // Pass back threshold value on WB

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [NBITS_KP-1:0] trigger_control_K_P = STARTING_KP; // P Parameter for control loop. 
                                            // This is the fraction of error value to change threshold by.


    // TODO Plan:   Use two state machines, one for this module's communication
    //              and one for managing the thresholds/rates. Both can be on the WB clock  
    //              since this is slow control.
    // Note: Completely unimplemented below this point
    // Note Note: Need to check whether this additional layer hurts timing. Don't expect so.

    ////////////////////////////////////////////////////////
    //////        Wishbone FSM stolen from AGC        //////
    ////////////////////////////////////////////////////////

    always @(posedge wb_clk_i) begin
        
        // Determine what we are doing this cycle
        case (state)
            IDLE: if (wb_threshold_cyc_i && wb_stb_i) begin
                if (wb_we_i) state <= WRITE;
                else state <= READ;
            end
            WRITE: state <= ACK;
            READ: state <= ACK;
            ACK: state <= IDLE;
            default: state <= IDLE; // Should never go here
        endcase
        
        // If reading, load the response in
        if (state == READ) begin
            if(wb_adr_i[8]) response_reg <= trigger_count_wb_reg[wb_adr_i[7:0]];
            else response_reg = trigger_count_done;
        end
        // If writing to a threshold, put it in the appropriate register
        if (state == WRITE) begin
            if (wb_adr_i[8]) begin // The 8th bit is used to indicate a threshold write
                if (wb_sel_i[0]) threshold_regs[wb_adr_i[7:0]][7:0] <= wb_dat_i[7:0];
                if (wb_sel_i[1]) threshold_regs[wb_adr_i[7:0]][15:8] <= wb_dat_i[15:8];
                if (wb_sel_i[2]) threshold_regs[wb_adr_i[7:0]][17:16] <= wb_dat_i[17:16];
            end             
        end
    end

    wire  [7:0][39:0] data_stage_connection;

    // trigger_chain_x8_wrapper #(.AGC_TIMESCALE_REDUCTION_BITS(AGC_TIMESCALE_REDUCTION_BITS))
    //             u_chain(
    //                 .wb_clk_i(wb_clk_i),
    //                 .wb_rst_i(wb_rst_i),
    //                 // `CONNECT_WBS_IFS( wb_bq_ , wb_bq_ ),//L
    //                 // `CONNECT_WBS_IFS( wb_agc_ , wb_agc_ ),
    //                 `CONNECT_WBS_IFM( wb_bq_ , bq_submodule_ ),//L
    //                 `CONNECT_WBS_IFM( wb_agc_ , agc_submodule_ ),
    //                 .reset_i(reset_i), 
    //                 .aclk(aclk),
    //                 .dat_i(dat_i),
    //                 .dat_o(data_stage_connection));

    // //TODO: Add holdoff at this stage!
    // assign trigger_o = trigger_signal_bit_o;

    // beamform_trigger #(.NBEAMS(NBEAMS)) 
    //     u_trigger(
    //         .clk_i(aclk),
    //         .data_i(data_stage_connection),

    //         .thresh_i(threshold_writing),
    //         .thresh_ce_i(trigger_threshold_ce_aclk),
    //         .update_i(trigger_threshold_update_aclk),        
            
    //         .trigger_o(trigger_signal_bit_o));



endmodule
