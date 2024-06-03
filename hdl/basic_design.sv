`timescale 1ns / 1ps
`include "interfaces.vh"
module basic_design(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 22, 32 ),
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

        `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf0_ , 128 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf1_ , 128 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf2_ , 128 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf3_ , 128 )
    );

    reg ack = 0;
    always @(posedge wb_clk_i) ack <= wb_cyc_i && wb_stb_i;
    assign wb_dat_o = "BSC0";
    assign wb_ack_o = ack && wb_cyc_i;
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;

    `define AXIS_ASSIGN( from , to ) \
        assign to``tdata = from``tdata;         \
        assign to``tvalid = from``tvalid;       \
        assign from``tready = to``tready
    
    `AXIS_ASSIGN( adc0_ , buf0_ );
    `AXIS_ASSIGN( adc1_ , buf1_ );
    `AXIS_ASSIGN( adc2_ , buf2_ );
    `AXIS_ASSIGN( adc3_ , buf3_ );
        
endmodule
