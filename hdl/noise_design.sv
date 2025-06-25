`timescale 1ns / 1ps
`include "interfaces.vh"
module noise_design(
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
    
    wire [7:0][127:0] sim_data_wires;
    reg [1:0] dly = 2'b00;

    assign wb_ack_o = dly[1];
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;
    assign wb_dat_o = 1'b0;

    always @(posedge aclk) begin
        dly[0] = wb_cyc_i;
        dly[1] = dly[0];
    end

    genvar i;
    generate
        for(i=0; i<8; i++) begin
            Gaussian12b_LFSR #(.SEED_BASE(i*256)) data_sim ( .clk(aclk),
                                                                .rst_i(wb_adr_i[0] && wb_cyc_i),
                                                                .sim_data(sim_data_wires[i])
            );
        end
    endgenerate

    `AXIS_ASSIGN( adc0_ , buf2_ );
    `AXIS_ASSIGN( adc1_ , buf3_ );
    // `AXIS_ASSIGN( matchdat0_ , buf2_ );
    // `AXIS_ASSIGN( matchdat1_ , buf3_ );
    // you can't doubly-assign an AXI4-Stream using the AXIS_ASSIGN
    // macros because it doubly-ties the tready signals
    // (e.g. it does assign matchdat0_tready = buf2_tready above,
    // then assign matchdat0_tready = dac0_tready here.
    // it doesn't really matter since we ignore treadys anyway.
    assign dac0_tdata = sim_data_wires[0];
    assign dac0_tvalid = 1'b1;
    assign dac1_tdata = sim_data_wires[1];
    assign dac1_tvalid  = 1'b1;

    assign buf0_tdata = sim_data_wires[0];
    assign buf0_tvalid = 1'b1;
    assign buf1_tdata = sim_data_wires[1];
    assign buf1_tvalid  = 1'b1;

endmodule
