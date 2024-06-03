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
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf3_ , 128 ),

	`HOST_NAMED_PORTS_AXI4S_MIN_IF( dac0_ , 128 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( dac1_ , 128 )
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
   
    reg ack = 0;
    always @(posedge wb_clk_i) ack <= wb_cyc_i && wb_stb_i;
    assign wb_dat_o = "BSC0";
    assign wb_ack_o = ack && wb_cyc_i;
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;

    wire [95:0] filt_out[3:0];
   
    shannon_whitaker_lpfull_v2 #(.NBITS(12),.OUTQ_INT(12),.OUTQ_FRAC(0)) 
      u_lpfull( .clk_i(aclk),
		.in_i(unpack(adc0_tdata)),
		.out_o( filt_out[0] ) );
    shannon_whitaker_lpfull_v2 #(.NBITS(12),.OUTQ_INT(12),.OUTQ_FRAC(0)) 
      u_lpfull( .clk_i(aclk),
		.in_i(unpack(adc1_tdata)),
		.out_o( filt_out[1] ) );
    shannon_whitaker_lpfull_v2 #(.NBITS(12),.OUTQ_INT(12),.OUTQ_FRAC(0)) 
      u_lpfull( .clk_i(aclk),
		.in_i(unpack(adc2_tdata)),
		.out_o( filt_out[2] ) );
    shannon_whitaker_lpfull_v2 #(.NBITS(12),.OUTQ_INT(12),.OUTQ_FRAC(0)) 
      u_lpfull( .clk_i(aclk),
		.in_i(unpack(adc3_tdata)),
		.out_o( filt_out[3] ) );

   `define ASSIGN( f, t) \
        assign f``tdata = pack(t);  \
        assign f``tvalid = 1'b1
       
   `ASSIGN( buf0_ , filt_out[0] );
   `ASSIGN( buf1_ , filt_out[1] );
   `ASSIGN( buf2_ , filt_out[2] );
   `ASSIGN( buf3_ , filt_out[3] );   

   `ASSIGN( dac0_ , filt_out[0] );
   `ASSIGN( dac1_ , filt_out[0] );
           
endmodule
