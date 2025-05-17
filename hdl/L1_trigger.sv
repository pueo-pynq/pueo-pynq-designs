`timescale 1ns / 1ps
`include "interfaces.vh"

// Pre-trigger filter chain.
// 1) Shannon-Whitaker low pass filter
// 2) Two Biquads in serial (to be used as notches)
// 3) AGC and 12->5 bit conversion
module L1_trigger #(parameter NBEAMS=2, parameter AGC_TIMESCALE_REDUCTION_BITS = 2)(  

        input wb_clk_i,
        input wb_rst_i,

        // Wishbone stuff for writing in coefficients to the biquads
        `TARGET_NAMED_PORTS_WB_IF( wb_bq_ , 22, 32 ), // Address width, data width. 

        // Wishbone stuff for writing to the AGC
        `TARGET_NAMED_PORTS_WB_IF( wb_agc_ , 22, 32 ), // Address width, data width.

        // Beam Thresholds
        input [17:0] thresh_i,
        input [NBEAMS-1:0] thresh_ce_i,
        input update_i,    
        
        // Control to capture the output to the RAM buffer
        input reset_i, 
        input aclk,
        input [7:0][95:0] dat_i,
        
        output [NBEAMS-1:0] trigger_o
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



    trigger_chain_x8_wrapper #(.AGC_TIMESCALE_REDUCTION_BITS(AGC_TIMESCALE_REDUCTION_BITS))
                u_chain(
                    .wb_clk_i(wb_clk_i),
                    .wb_rst_i(wb_rst_i),
                    `CONNECT_WBS_IFS( wb_bq_ , wb_bq_ ),//L
                    `CONNECT_WBS_IFS( wb_agc_ , wb_agc_ ),
                    .reset_i(reset_i), 
                    .aclk(aclk),
                    .dat_i(dat_i),
                    .dat_o(data_stage_connection));

    wire  [7:0][39:0] data_stage_connection;

    beamform_trigger #(.NBEAMS(2)) 
        u_trigger(
            .clk_i(aclk),
            .data_i(data_stage_connection),

            .thresh_i(thresh_i),
            .thresh_ce_i(thresh_ce_i),
            .update_i(update_i),        
            
            .trigger_o(trigger_o));



endmodule
