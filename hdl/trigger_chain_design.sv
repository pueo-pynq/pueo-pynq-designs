`timescale 1ns / 1ps
`include "interfaces.vh"

// Pre-trigger filter chain.
// 1) Shannon-Whitaker low pass filter
// 2) Two Biquads in serial (to be used as notches)
// TODO Make fixed point parameterizable
module trigger_chain_design(        
        input wb_clk_i,
        input wb_rst_i,

        // Wishbone stuff for writing in coefficients to the biquads
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 22, 32 ), // Address width, data width. Address is at size limit

        // Wishbone stuff for writing to the AGC
        `TARGET_NAMED_PORTS_WB_IF( wb_agc_ , 22, 32 ), // Address width, data width. Address is at size limit
        
        // Control to capture the output to the RAM buffer
        input reset_i, 
        input aclk,
        input [95:0] dat_i,
        
        output [39:0] dat_o,
        output [95:0] probes
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

    wire [95:0] data_stage_connection [1:0]; // In 12 bits since that's what the LPF works in

    // Low pass filter

    shannon_whitaker_lpfull_v2 u_lpf (  .clk_i(aclk),
                                        .in_i(dat_i),
                                        .out_o(data_stage_connection[0]));

    assign probes = data_stage_connection[0];
    wire [95:0] probe_to_nowhere[1:0];

    // Biquads

    biquad8_double_design u_biquadx2(
        .wb_clk_i(wb_clk_i),
        .wb_rst_i(wb_rst_i),        
        `CONNECT_WBS_IFS( wb_ , wb_ ),
        .reset_BQ_i(reset_i),
        .aclk(aclk),
        .dat_i(data_stage_connection[0]),
        .dat_o(data_stage_connection[1]),
        .probes(probe_to_nowhere[0])
    );

    agc_design_minimal u_agc_design_minimal(
        .wb_clk_i(wb_clk_i),
        .wb_rst_i(wb_rst_i),        
        `CONNECT_WBS_IFS( wb_ , wb_agc_ ),
        .aclk(aclk),
        .aresetn(reset_i),
        .dat_i(dat_i),//(data_stage_connection[1]),
        
        .dat_o(dat_o),
        .probes(probe_to_nowhere[1])
    );


endmodule
