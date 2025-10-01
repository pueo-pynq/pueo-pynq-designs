`timescale 1ns / 1ps
`include "interfaces.vh"
module lowampa_design #(parameter NBEAMS=2, parameter AGC_TIMESCALE_REDUCTION_BITS = 2)(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 22, 32 ),
        input aclk,
        input aresetn,
        input capture_waiting,
        output reg capture_enable = 1,
        output trigger,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc0_ , 64 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc1_ , 64 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc2_ , 64 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc3_ , 64 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc4_ , 64 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc5_ , 64 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc6_ , 64 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc7_ , 64 ),

        `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf0_ , 128 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf1_ , 128 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf2_ , 128 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf3_ , 128 ),

	    `HOST_NAMED_PORTS_AXI4S_MIN_IF( dac0_ , 128 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( dac1_ , 128 )
    );
    
    wire aclk_phase_i;
    reg [1:0] aclk_cnt = 0;
    localparam aclk_cycle_length = 3;
    always @(posedge aclk)
    begin
      if(aclk_cnt<aclk_cycle_length-1)
      begin
        aclk_cnt <= aclk_cnt+1;
      end
      else
      begin
        aclk_cnt <= 0;
      end
    end
    assign aclk_phase_i = (aclk_cnt ==0);
    
    
 // UNPACK is 128 -> 96
    function [47:0] unpack;
        input [63:0] data_in;
        integer i;
        begin
            for (i=0;i<4;i=i+1) begin
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

    wire [7:0][47:0] repacked_data;
    assign repacked_data[0] = unpack(adc0_tdata);
    assign repacked_data[1] = unpack(adc1_tdata);
    assign repacked_data[2] = unpack(adc2_tdata);
    assign repacked_data[3] = unpack(adc3_tdata);
    assign repacked_data[4] = unpack(adc4_tdata);
    assign repacked_data[5] = unpack(adc5_tdata);
    assign repacked_data[6] = unpack(adc6_tdata);
    assign repacked_data[7] = unpack(adc7_tdata);

    // REPACK updacked ADC into dat_i


    wire [3:0][19:0] dat_o;
    wire [3:0][1:0][47:0] dat_debug;
    wire [NBEAMS-1:0] trig_out;
    wire [223:0] debug_envelope;
    reg [223:0] debug_envelope_store1;
    reg [223:0] debug_envelope_store2;
    reg [223:0] debug_envelope_store3;
    
    always @(posedge aclk)
    begin
      debug_envelope_store1 <= debug_envelope;
      debug_envelope_store2 <= debug_envelope_store1;
      debug_envelope_store3 <= debug_envelope_store2;
    end

    lowampa_trigger_wrapper #(
        .AGC_TIMESCALE_REDUCTION_BITS(2),
        .NBEAMS(NBEAMS),
        .WBCLKTYPE("PSCLK"),
        .CLKTYPE("ACLK"),
        .IFCLKTYPE("ACLK")
    ) u_lowampa_trigger_wrapper (
        .wb_clk_i(wb_clk_i),
        .wb_rst_i(wb_rst_i),
        `CONNECT_WBS_IFS( wb_ , wb_), // Pass right through (s to s)
        .aclk(aclk),
        .aclk_phase_i(aclk_phase_i),
        
        .tclk(aclk),
        .dat_i(repacked_data),
        .debug_envelope(debug_envelope),
        
        //.reset_i(reset_i), 
                    
        .ifclk(aclk),
        .ifclk_running_i(),
        .runrst_i(),
        .runstop_i(),
        
        //.dat_o(dat_o),
        .dat_debug(dat_debug)//,
        //.trigger_o(trig_out)
    );

    assign trigger = (trig_out!=0);
    
    wire [95:0] long_repacked_data;
    reg [47:0] repacked_data_store = 48'b0;
    assign long_repacked_data = {repacked_data[0],repacked_data_store};
    always @(posedge aclk)
    begin
        repacked_data_store <= repacked_data[0];
    end
    
//    wire [95:0] long_repacked_data2;
//    reg [47:0] repacked_data_store2 = 48'b0;
//    assign long_repacked_data2 = {repacked_data[6],repacked_data_store2};
//    always @(posedge aclk)
//    begin
//        repacked_data_store2 <= repacked_data[6];
//    end
    
//    wire [95:0] long_repacked_data3;
//    reg [47:0] repacked_data_store3 = 48'b0;
//    assign long_repacked_data3 = {repacked_data[4],repacked_data_store3};
//    always @(posedge aclk)
//    begin
//        repacked_data_store3 <= repacked_data[4];
//    end

//    wire [95:0] long_repacked_data4;
//    reg [47:0] repacked_data_store4 = 48'b0;
//    assign long_repacked_data4 = {repacked_data[6],repacked_data_store4};
//    always @(posedge aclk)
//    begin
//        repacked_data_store4 <= repacked_data[6];
//    end
    
//    reg [63:0] previous_signed_envelope;
//    wire [63:0] beamforming_signed_envelope;
//    assign beamforming_signed_envelope = {{8{debug_envelope[103]}},debug_envelope[103:96],{8{debug_envelope[71]}},debug_envelope[71:64],{8{debug_envelope[39]}},debug_envelope[39:32],{8{debug_envelope[7]}},debug_envelope[7:0]};
//    always @(posedge aclk)
//    begin
//        previous_signed_envelope <= beamforming_signed_envelope;
//    end


//    reg [63:0] previous_signed_envelope2;
//    wire [63:0] beamforming_signed_envelope2;
//    assign beamforming_signed_envelope2 = {{8{debug_envelope[111]}},debug_envelope[111:104],{8{debug_envelope[79]}},debug_envelope[79:72],{8{debug_envelope[47]}},debug_envelope[47:40],{8{debug_envelope[15]}},debug_envelope[15:8]};
//    always @(posedge aclk)
//    begin
//        previous_signed_envelope2 <= beamforming_signed_envelope2;
//    end


//    reg [63:0] previous_signed_envelope3;
//    wire [63:0] beamforming_signed_envelope3;
//    assign beamforming_signed_envelope3 = {{8{debug_envelope[119]}},debug_envelope[119:112],{8{debug_envelope[87]}},debug_envelope[87:80],{8{debug_envelope[55]}},debug_envelope[55:48],{8{debug_envelope[23]}},debug_envelope[23:16]};
//    always @(posedge aclk)
//    begin
//        previous_signed_envelope3 <= beamforming_signed_envelope3;
//    end


//    reg [63:0] previous_signed_envelope4;
//    wire [63:0] beamforming_signed_envelope4;
//    assign beamforming_signed_envelope4 = {{8{debug_envelope[127]}},debug_envelope[127:120],{8{debug_envelope[95]}},debug_envelope[95:88],{8{debug_envelope[63]}},debug_envelope[63:56],{8{debug_envelope[31]}},debug_envelope[31:24]};
//    always @(posedge aclk)
//    begin
//        previous_signed_envelope4 <= beamforming_signed_envelope4;
//    end
    
    reg [63:0] previous_square;
    wire [63:0] beamforming_square;
    assign beamforming_square = debug_envelope[191:128];
    always @(posedge aclk)
    begin
        previous_square <= beamforming_square;
    end
    
    reg [63:0] previous_envelope;
    wire [63:0] beamforming_envelope;
    assign beamforming_envelope = {debug_envelope[207:192],debug_envelope[207:192],debug_envelope[207:192],debug_envelope[207:192]};
    always @(posedge aclk)
    begin
        previous_envelope <= beamforming_envelope;
    end
    
    reg [63:0] previous_envelope2;
    wire [63:0] beamforming_envelope2;
    assign beamforming_envelope2 = {debug_envelope[223:208],debug_envelope[223:208],debug_envelope[223:208],debug_envelope[223:208]};
    always @(posedge aclk)
    begin
        previous_envelope2 <= beamforming_envelope2;
    end
    
    wire [95:0] long_repacked_lowpass_data;
    reg [47:0] repacked_lowpass_data_store = 48'b0;
    assign long_repacked_lowpass_data = {dat_debug[0][0],repacked_lowpass_data_store};
    always @(posedge aclk)
    begin
        repacked_lowpass_data_store <= {dat_debug[0][0]};
    end
    
    wire [95:0] long_repacked_matched_data;
    reg [47:0] repacked_matched_data_store = 48'b0;
    assign long_repacked_matched_data = {dat_debug[0][1],repacked_matched_data_store};
    always @(posedge aclk)
    begin
        repacked_matched_data_store <= dat_debug[0][1];
    end
    
//    wire [39:0] long_repacked_dat;
//    reg [19:0] repacked_dat_store = 20'b0;
//    assign long_repacked_dat = {dat_o[0],repacked_dat_store};
//    always @(posedge aclk)
//    begin
//        repacked_dat_store <= dat_o[0];
//    end
    
    
    `ASSIGN( buf0_ , long_repacked_matched_data);
//    `ASSIGN( buf1_ , long_repacked_lowpass_data);
//    `ASSIGN( buf2_ , long_repacked_matched_data);
//    `ASSIGN( buf3_ , long_repacked_lowpass_data);
    //`ASSIGN( buf3_ , trigger );           
//    assign buf0_tdata = {beamforming_signed_envelope,previous_signed_envelope};
//    assign buf0_tvalid = 1'b1;
    assign buf1_tdata = {beamforming_square,previous_square};
    assign buf1_tvalid = 1'b1;
//    assign buf2_tdata = {beamforming_square,previous_square};
//    assign buf2_tvalid = 1'b1;
//    `ASSIGN( buf2_ , long_repacked_data3);
    //`ASSIGN( buf3_ , trigger );           
    assign buf2_tdata = {beamforming_envelope,previous_envelope};
    assign buf2_tvalid = 1'b1;
    assign buf3_tdata = {beamforming_envelope2,previous_envelope2};
    assign buf3_tvalid = 1'b1;
    // `ASSIGN( buf0_ , filt_out[4] );
    // `ASSIGN( buf1_ , filt_out[5] );
    // `ASSIGN( buf2_ , filt_out[6] );
    // `ASSIGN( buf3_ , filt_out[7] ); 

    `ASSIGN( dac0_ , repacked_data[0] );
    `ASSIGN( dac1_ ,  repacked_data[1] );
    // `ASSIGN( dac0_ , filt_out[2] );
    // `ASSIGN( dac1_ , filt_out[3] );
    // `ASSIGN( dac0_ , filt_out[4] );
    // `ASSIGN( dac1_ , filt_out[5] );
    // `ASSIGN( dac0_ , filt_out[6] );
    // `ASSIGN( dac1_ , filt_out[7] );
           
endmodule
