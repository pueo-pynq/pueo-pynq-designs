`timescale 1ns / 1ps
`include "interfaces.vh"
module biquad8_design(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 22, 32 ),        
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
    
    // dumb testing    
    `DEFINE_WB_IF( bq0_ , 7, 32);
    `DEFINE_WB_IF( bq1_ , 7, 32);
    // stupidest intercon ever
    assign wb_ack_o = (wb_adr_i[7]) ? bq1_ack_i : bq0_ack_i;
    assign wb_err_o = (wb_adr_i[7]) ? bq1_err_i : bq0_err_i;
    assign wb_rty_o = (wb_adr_i[7]) ? bq1_rty_i : bq0_rty_i;
    assign wb_dat_o = (wb_adr_i[7]) ? bq1_dat_i : bq0_dat_i;
    
    assign bq0_cyc_o = wb_cyc_i && !wb_adr_i[7];
    assign bq1_cyc_o = wb_cyc_i && wb_adr_i[7];
    assign bq0_stb_o = wb_stb_i;
    assign bq1_stb_o = wb_stb_i;
    assign bq0_adr_o = wb_adr_i[6:0];
    assign bq1_adr_o = wb_adr_i[6:0];
    assign bq0_dat_o = wb_dat_i;
    assign bq1_dat_o = wb_dat_i;
    assign bq0_we_o = wb_we_i;
    assign bq1_we_o = wb_we_i;
    assign bq0_sel_o = wb_sel_i;
    assign bq1_sel_o = wb_sel_i;
    
    // To test the biquad8_pole_fir we
    // need to do a bit of jiggery-pokery.
    // 
    `DEFINE_AXI4S_MIN_IF( gate0_ , 128);
    `DEFINE_AXI4S_MIN_IF( gate1_ , 128);
    // these are the outputs
    wire [95:0] bq_out[1:0];
    `DEFINE_AXI4S_MIN_IF( bqdat0_ , 128);
    `DEFINE_AXI4S_MIN_IF( bqdat1_ , 128);
    assign bqdat0_tdata = pack(bq_out[0]);
    assign bqdat0_tvalid = 1'b1;
    assign bqdat1_tdata = pack(bq_out[1]);
    assign bqdat1_tvalid = 1'b1;
                
    reg [127:0] adc0_rereg = {128{1'b0}};
    reg [127:0] adc1_rereg = {128{1'b0}};
    reg adc_gate = 0;
    reg [1:0] capture_rereg = {2{1'b0}};
    wire capture_delay;
    wire mid_gate_delay;
    wire gate_delay_done;
    SRLC32E u_gate_delay(.D(capture_rereg[0] && !capture_rereg[1]),
                         .CLK(aclk),
                         .CE(1'b1),
                         .Q31(capture_delay));
    SRLC32E u_delay_mid(.D(capture_delay),
                        .CLK(aclk),
                        .CE(1'b1),
                        .Q31(mid_gate_delay));                           
    SRLC32E u_delay_done(.D(mid_gate_delay),
                         .CLK(aclk),
                         .CE(1'b1),
                         .Q31(gate_delay_done));                                 
    always @(posedge aclk) begin
        if (capture_delay) adc_gate <= 1'b1;
        else if (gate_delay_done) adc_gate <= 1'b0;
        
        if (adc_gate) adc0_rereg <= adc0_tdata;
        else adc0_rereg <= {128{1'b0}};
        
        if (adc_gate) adc1_rereg <= adc1_tdata;
        else adc1_rereg <= {128{1'b0}};
    end
    
    assign gate0_tdata = adc0_rereg;
    assign gate0_tvalid = 1'b1;
    
    assign gate1_tdata = adc1_rereg;
    assign gate1_tvalid = 1'b1;
    
    biquad8_wrapper #(.NBITS(12),
                      .NFRAC(0),
                      .NSAMP(8),
                      .OUTBITS(12),
                      .OUTFRAC(0),
                      .WBCLKTYPE("PSCLK"),
                      .CLKTYPE("ACLK"))
        u_biquad8_A(.wb_clk_i(ps_clk),
                  .wb_rst_i(1'b0),
                  `CONNECT_WBS_IFM( wb_ , bq0_ ),
                  .clk_i(aclk),
                  .global_update_i(1'b0),
                  .dat_i(unpack(gate0_tdata)),
                  .dat_o(bq_out[0]));   

    biquad8_wrapper #(.NBITS(12),
                      .NFRAC(0),
                      .NSAMP(8),
                      .OUTBITS(12),
                      .OUTFRAC(0),
                      .WBCLKTYPE("PSCLK"),
                      .CLKTYPE("ACLK"))
        u_biquad8_B(.wb_clk_i(ps_clk),
                  .wb_rst_i(1'b0),
                  `CONNECT_WBS_IFM( wb_ , bq1_ ),
                  .clk_i(aclk),
                  .global_update_i(1'b0),
                  .dat_i(unpack(gate1_tdata)),
                  .dat_o(bq_out[1]));   

    `AXIS_ASSIGN( gate0_ , buf0_ );
    `AXIS_ASSIGN( gate1_ , buf1_ );
    `AXIS_ASSIGN( bqdat0_ , buf2_ );
    `AXIS_ASSIGN( bqdat1_ , buf3_ );

    `AXIS_ASSIGN( bqdat0_ , dac0_ );
    `AXIS_ASSIGN( bqdat1_ , dac1_ );

endmodule
