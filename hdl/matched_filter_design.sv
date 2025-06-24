`timescale 1ns / 1ps
`include "interfaces.vh"
module matched_filter_design(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 22, 32 ), // Address width, data width. Address is at size limit
        input capture_i,
        input aclk,
        input aresetn,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc0_ , 128 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc1_ , 128 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc2_ , 128 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc3_ , 128 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc4_ , 128 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc5_ , 128 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc6_ , 128 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc7_ , 128 ),
        // outputs to buffers
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf0_ , 128 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf1_ , 128 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf2_ , 128 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf3_ , 128 ),
        // outputs to DACs        
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( dac0_ , 128 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( dac1_ , 128 )
    );

    // silliness

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


    `define AXIS_ASSIGN( from , to ) \
        assign to``tdata = from``tdata;         \
        assign to``tvalid = from``tvalid;       \
        assign from``tready = to``tready
    
    // To test the biquad8_pole_fir we
    // need to do a bit of jiggery-pokery.
    // 
    // these are the outputs
    wire [95:0] match_out[1:0];
    `DEFINE_AXI4S_MIN_IF( matchdat0_ , 128);
    `DEFINE_AXI4S_MIN_IF( matchdat1_ , 128);
    assign matchdat0_tdata = pack(match_out[0]);
    assign matchdat0_tvalid = 1'b1;
    assign matchdat1_tdata = pack(match_out[1]);
    assign matchdat1_tvalid = 1'b1;

    matched_filter u_matched_filter0(
        .aclk(aclk),
        .data_i(unpack(adc0_tdata)),
        .data_o(match_out[0])
    );

        matched_filter u_matched_filter1(
        .aclk(aclk),
        .data_i(unpack(adc1_tdata)),
        .data_o(match_out[1])
    );

    `AXIS_ASSIGN( adc0_ , buf0_ );
    `AXIS_ASSIGN( adc1_ , buf1_ );
    `AXIS_ASSIGN( matchdat0_ , buf2_ );
    `AXIS_ASSIGN( matchdat1_ , buf3_ );
    // you can't doubly-assign an AXI4-Stream using the AXIS_ASSIGN
    // macros because it doubly-ties the tready signals
    // (e.g. it does assign matchdat0_tready = buf2_tready above,
    // then assign matchdat0_tready = dac0_tready here.
    // it doesn't really matter since we ignore treadys anyway.
    assign dac0_tdata = matchdat0_tdata;
    assign dac0_tvalid = matchdat0_tvalid;
    assign dac1_tdata = adc0_tdata;
    assign dac1_tvalid = adc0_tvalid;

endmodule
