`timescale 1ns / 1ps
`include "interfaces.vh"

// Check whether the bits selecting the channel match the value
// TODO FIXME for multiple ADDR locations
`define CHAN_ADDR_MATCH( in, val ) ( {in[10:8], 8'b00000000} == val)

// 8 channels of trigger chain, with wisbone interconnect
module trigger_chain_x8_wrapper #(parameter AGC_TIMESCALE_REDUCTION_BITS = 2)(  

        input wb_clk_i,
        input wb_rst_i,

        // Wishbone stuff for writing in coefficients to the biquads
        `TARGET_NAMED_PORTS_WB_IF( wb_bq_ , 22, 32 ), // Address width, data width. Address is at size limit

        // Wishbone stuff for writing to the AGC
        `TARGET_NAMED_PORTS_WB_IF( wb_agc_ , 22, 32 ), // Address width, data width. Address is at size limit
        
        // Control to capture the output to the RAM buffer
        input reset_i, 
        input aclk,
        input [95:0] dat_i [7:0],
        
        output [39:0] dat_o [7:0]
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

    // This may be completely unnecessary due to the loop already differentiating the channels
    `define CHAN_NUM ( n ) _``n``_ 
    localparam [21:0] CHAN_MASK = 22'h000000;

    wire        wb_bq_ack_o_vec [7:0];
    wire        wb_bq_err_o_vec [7:0];
    wire        wb_bq_rty_o_vec [7:0];
    wire [31:0] wb_bq_dat_o_vec [7:0];

    genvar idx;
    generate
        for(idx = 0; i<8; i = i+1) begin : TRIGGER_CHAIN_LOOP
            `DEFINE_WB_IF( wb_bq`CHAN_NUM(idx), 7, 32);
            `DEFINE_WB_IF( wb_agc`CHAN_NUM(idx), 21, 32);

            assign wb_bq_ack_o_vec[idx] = wb_bq`CHAN_NUM(idx)ack_o;
            assign wb_bq_err_o_vec[idx] = wb_bq`CHAN_NUM(idx)err_o;
            assign wb_bq_rty_o_vec[idx] = wb_bq`CHAN_NUM(idx)rty_o;
            assign wb_bq_dat_o_vec[idx] = wb_bq`CHAN_NUM(idx)dat_o;

            // The cyc signal controls whether anything happens
            assign wb_bq`CHAN_NUM(idx)cyc_o = wb_agc_cyc_i && CHAN_ADDR_MATCH(wb_bq_adr_i, idx * 10'h100);
            assign wb_bq`CHAN_NUM(idx)stb_o = wb_bq_stb_i;
            assign wb_bq`CHAN_NUM(idx)adr_o = wb_bq_adr_i[6:0];
            assign wb_bq`CHAN_NUM(idx)dat_o = wb_bq_dat_i;
            assign wb_bq`CHAN_NUM(idx)we_o  = wb_bq_we_i;
            assign wb_bq`CHAN_NUM(idx)sel_o = wb_bq_sel_i;


            // The cyc signal controls whether anything happens
            // TODO FIXME
            assign wb_agc`CHAN_NUM(idx)cyc_o = wb_agc_cyc_i && CHAN_ADDR_MATCH(wb_agc_adr_i, idx * 10'h100)// TOO LOW OF BITS;
            assign wb_agc`CHAN_NUM(idx)stb_o = wb_agc_stb_i;
            assign wb_agc`CHAN_NUM(idx)adr_o = wb_agc_adr_i[21:0];
            assign wb_agc`CHAN_NUM(idx)dat_o = wb_agc_dat_i;
            assign wb_agc`CHAN_NUM(idx)we_o  = wb_agc_we_i;
            assign wb_agc`CHAN_NUM(idx)sel_o = wb_agc_sel_i;

            trigger_chain_wrapper #(.TIMESCALE_REDUCTION(2**TIMESCALE_REDUCTION_BITS))
            u_chain(
                .wb_clk_i(wbclk),
                .wb_rst_i(1'b0),
                `CONNECT_WBS_IFM( wb_bq_ , wb_bq`CHAN_NUM(idx) ),
                `CONNECT_WBS_IFM( wb_agc_ , wb_agc`CHAN_NUM(idx) ),
                .reset_i(reset_i), 
                .aclk(aclk),
                .dat_i(dat_i[idx]),
                .dat_o(dat_o[idx]));
            end;
    endgenerate

    

endmodule

`undef CHAN_NUM
`undef ADDR_MATCH_MASK