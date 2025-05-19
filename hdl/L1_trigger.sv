`timescale 1ns / 1ps
`include "interfaces.vh"

// Pre-trigger filter chain.
// 1) Shannon-Whitaker low pass filter
// 2) Two Biquads in serial (to be used as notches)
// 3) AGC and 12->5 bit conversion
module L1_trigger #(parameter NBEAMS=2, parameter AGC_TIMESCALE_REDUCTION_BITS = 2)(  

        input wb_clk_i,
        input wb_rst_i,

        // One wishbone interface to control both AGC and Biquads
        // Bit 12 differentiates between the two (0 for AGC, 1 for BQs)
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 22, 32 ), // Address width, data width.

        // // Wishbone stuff for writing in coefficients to the biquads
        // `TARGET_NAMED_PORTS_WB_IF( wb_bq_ , 22, 32 ), // Address width, data width. 

        // // Wishbone stuff for writing to the AGC
        // `TARGET_NAMED_PORTS_WB_IF( wb_agc_ , 22, 32 ), // Address width, data width.

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
 
    // Wishbone connection split between AGC and Biquads
    // Use bit 12 to differentiate, 0 for AGC 1 for Biquad
    // These interfaces are host-named (M). Sine the ports of this module are target-named,
    // there needs to be crossover
    `DEFINE_WB_IF( agc_submodule_ , 22, 32);
    `DEFINE_WB_IF( bq_submodule_ , 22, 32);
    //  Top interface target (S)        Connection interface (M)
    assign wb_ack_o = (wb_adr_i[12]) ? bq_submodule_ack_i : agc_submodule_ack_i;
    assign wb_err_o = (wb_adr_i[12]) ? bq_submodule_err_i : agc_submodule_err_i;
    assign wb_rty_o = (wb_adr_i[12]) ? bq_submodule_rty_i : agc_submodule_rty_i;
    assign wb_dat_o = (wb_adr_i[12]) ? bq_submodule_dat_i : agc_submodule_dat_i;
    
    assign agc_submodule_cyc_o = wb_cyc_i && !wb_adr_i[12];
    assign bq_submodule_cyc_o = wb_cyc_i && wb_adr_i[12];
    assign agc_submodule_stb_o = wb_stb_i;
    assign bq_submodule_stb_o = wb_stb_i;
    assign agc_submodule_adr_o = wb_adr_i;
    assign bq_submodule_adr_o = wb_adr_i;
    assign agc_submodule_dat_o = wb_dat_i;
    assign bq_submodule_dat_o = wb_dat_i;
    assign agc_submodule_we_o = wb_we_i;
    assign bq_submodule_we_o = wb_we_i;
    assign agc_submodule_sel_o = wb_sel_i;
    assign bq_submodule_sel_o = wb_sel_i;


    trigger_chain_x8_wrapper #(.AGC_TIMESCALE_REDUCTION_BITS(AGC_TIMESCALE_REDUCTION_BITS))
                u_chain(
                    .wb_clk_i(wb_clk_i),
                    .wb_rst_i(wb_rst_i),
                    // `CONNECT_WBS_IFS( wb_bq_ , wb_bq_ ),//L
                    // `CONNECT_WBS_IFS( wb_agc_ , wb_agc_ ),
                    `CONNECT_WBS_IFM( wb_bq_ , bq_submodule_ ),//L
                    `CONNECT_WBS_IFM( wb_agc_ , agc_submodule_ ),
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
