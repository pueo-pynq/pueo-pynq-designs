`timescale 1ns / 1ps
`include "interfaces.vh"
module filter_chain_design #(parameter NBEAMS=2, parameter AGC_TIMESCALE_REDUCTION_BITS = 2)(
    input wb_clk_i,
    input wb_rst_i,
    `TARGET_NAMED_PORTS_WB_IF( wb_ , 22, 32 ),

    input aclk,
    input reset_i,

    `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc0_ , 128 ),
    `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc1_ , 128 ),
    `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc2_ , 128 ),
    `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc3_ , 128 ),
    `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc4_ , 128 ),
    `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc5_ , 128 ),
    `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc6_ , 128 ),
    `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc7_ , 128 ),

    `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf0_ , 128 ),
    `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf1_ , 128 ),
    // `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf2_ , 128 ),
    // `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf3_ , 128 ),
    // `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf4_ , 128 ),
    // `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf5_ , 128 ),
    // `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf6_ , 128 ),
    // `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf7_ , 128 ),

    `HOST_NAMED_PORTS_AXI4S_MIN_IF( dac0_ , 128 ),
    `HOST_NAMED_PORTS_AXI4S_MIN_IF( dac1_ , 128 )
    // `HOST_NAMED_PORTS_AXI4S_MIN_IF( dac2_ , 128 ),
    // `HOST_NAMED_PORTS_AXI4S_MIN_IF( dac3_ , 128 ),
    // `HOST_NAMED_PORTS_AXI4S_MIN_IF( dac4_ , 128 ),
    // `HOST_NAMED_PORTS_AXI4S_MIN_IF( dac5_ , 128 ),
    // `HOST_NAMED_PORTS_AXI4S_MIN_IF( dac6_ , 128 ),
    // `HOST_NAMED_PORTS_AXI4S_MIN_IF( dac7_ , 128 )
    );

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
    // MIDPACK is 40 -> 128
    // Note that these values are stored not entirely MSB
    function [127:0] midpack;
        input [39:0] data_in;
        integer i;
        begin
            for (i=0;i<8;i=i+1) begin
                midpack[(16*i+9) +: 7] = {11{1'b0}};
                midpack[(16*i+4) +: 5] = data_in[5*i +: 5];
                midpack[(16*i) +: 4] = {4{1'b0}};
            end
        end
    endfunction


    `define ASSIGN( f, t) \
        assign f``tdata = pack(t);  \
        assign f``tvalid = 1'b1

    `define MIDASSIGN( f, t) \
        assign f``tdata = midpack(t);  \
        assign f``tvalid = 1'b1;

    wire [7:0][95:0] repacked_data;
    assign repacked_data[0] = unpack(adc0_tdata);
    assign repacked_data[1] = unpack(adc1_tdata);
    assign repacked_data[2] = unpack(adc2_tdata);
    assign repacked_data[3] = unpack(adc3_tdata);
    assign repacked_data[4] = unpack(adc4_tdata);
    assign repacked_data[5] = unpack(adc5_tdata);
    assign repacked_data[6] = unpack(adc6_tdata);
    assign repacked_data[7] = unpack(adc7_tdata);

    // REPACK updacked ADC into dat_i


    wire [7:0][39:0] dat_o;
    wire [7:0][1:0][95:0] dat_debug;
    wire [NBEAMS-1:0] trig_out;


    L1_trigger_wrapper #(
        .AGC_TIMESCALE_REDUCTION_BITS(2),
        .NBEAMS(NBEAMS)
    ) u_L1_trigger_wrapper (
        .wb_clk_i(wb_clk_i),
        .wb_rst_i(wb_rst_i),
        `CONNECT_WBS_IFS( wb_ , wb_), // Pass right through (s to s)
        .reset_i(reset_i), 
        .aclk(aclk),
        .dat_i(repacked_data),
                    
        .dat_o(dat_o),
        .dat_debug(dat_debug),
        .trigger_o(trig_out)
    );

        
    `ASSIGN( buf0_ , repacked_data[0] );
    `ASSIGN( buf1_ , dat_o[0]);
    // `ASSIGN( buf2_ , filt_out[2] );
    // `ASSIGN( buf3_ , filt_out[3] );           
    // `ASSIGN( buf0_ , filt_out[4] );
    // `ASSIGN( buf1_ , filt_out[5] );
    // `ASSIGN( buf2_ , filt_out[6] );
    // `ASSIGN( buf3_ , filt_out[7] ); 

    `ASSIGN( dac0_ , repacked_data[0] );
    `ASSIGN( dac1_ , dat_o[0] );
    // `ASSIGN( dac0_ , filt_out[2] );
    // `ASSIGN( dac1_ , filt_out[3] );
    // `ASSIGN( dac0_ , filt_out[4] );
    // `ASSIGN( dac1_ , filt_out[5] );
    // `ASSIGN( dac0_ , filt_out[6] );
    // `ASSIGN( dac1_ , filt_out[7] );
           
endmodule
