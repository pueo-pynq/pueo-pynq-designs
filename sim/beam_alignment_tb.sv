`timescale 1ns / 1ps
`include "interfaces.vh"
`include "L1Beams_header.vh"
module beam_alignment_tb;

    // parameter THIS_DESIGN = "ALIGNMENT";
    parameter   THIS_STIM = "GAUSS_AND_PULSE";
    parameter   ALIGNED_BEAM = 0;

    // Gaussian Random Parameters
    int seed = 1;
    int stim_mean = 15;
    int stim_sdev = 4; // Note that max value is 32
    int stim_val = 0;
    int cycling_num = 0;

    localparam  NBITS=5;
    localparam  NSAMP=8; 
    localparam  NCHAN=8;

    // Clocks
    wire clk;
    tb_rclk #(.PERIOD(5.0)) u_clk(.clk(clk));

    localparam NBEAMS = 46;

    // NOTE THE BIG-ENDIAN ARRAYS HERE
    localparam int delay_array [0:(`BEAM_TOTAL)-1][0:NCHAN-1] = `BEAM_ANTENNA_DELAYS;

    reg [39:0]          in_data_reg [7:0]   = {{40{1'b0}}, {40{1'b0}}, {40{1'b0}}, {40{1'b0}}, {40{1'b0}}, {40{1'b0}}, {40{1'b0}}, {40{1'b0}}};
    reg [17:0]          thresh_reg          = 18'd0;
    reg [NBEAMS-1:0]    thresh_ce_reg       = {NBEAMS{1'b0}};
    reg                 update_reg          = 1'b0;
    reg [NBEAMS-1:0]    trigger_reg; 

    wire [39:0]         in_data [7:0]       = in_data_reg;
    wire [17:0]         thresh              = thresh_reg;
    wire [NBEAMS-1:0]   thresh_ce           = thresh_ce_reg;
    wire        update                      = update_reg;
    wire [NBEAMS-1:0]   trigger;

    assign trigger_reg = trigger;

    // Do some vectorizing for debugging
    wire [7:0][4:0] vectorized_data [7:0];
    

    assign vectorized_data = in_data_reg;

    beam_alignment #(.NBEAMS(NBEAMS))
     u_beam_align(
        .clk_i(clk),
        .data_i(in_data),

        .thresh_i(thresh),
        .thresh_ce_i(thresh_ce),
        .update_i(update),
        .trigger_o(trigger)
    );


    initial begin : VALLOOP
        $display("Setup");
        for(int j=0; j<25; j=j+1) begin
            #1.75;
            @(posedge clk);
        end
        #1.75;
        @(posedge clk);
        #1.75;
        $display("Initial Threshold Load");
        for(int beam_idx=0; beam_idx<NBEAMS; beam_idx = beam_idx+2) begin
            update_reg = 1'b0;
            thresh_reg = 18'd6050; 
            thresh_ce_reg[beam_idx +: 2] = 2'b10; // Load this threshold into A.
            @(posedge clk);
            thresh_reg = 18'd6050; 
            thresh_ce_reg[beam_idx +: 2] = 2'b01; // Load this threshold into B.
            #1.75;
            @(posedge clk);
            update_reg = 1'b1; // Apply new thresholds
            #1.75;
            @(posedge clk);
            #1.75;
            thresh_ce_reg[beam_idx +: 2] = 2'b00;
            update_reg = 1'b0;
            @(posedge clk);
            #1.75;
        end
        for(int i=0; i<64; i=i+1) begin  
            @(posedge clk);
            #1.75;
        end
        $display("Initial Threshold Has Been Loaded");

        if (THIS_STIM == "ALIGNMENT") begin : ALIGNMENT_RUN
            forever begin
                for(int i=0; i<4; i=i+1) begin  
                    @(posedge clk);
                    #1.75;
                    for(int j=0; j<8; j=j+1) begin : CHANNEL_FILL
                        in_data_reg[j] = {{5'd7},{5'd6},{5'd5},{5'd4},{5'd3},{5'd2},{5'd1},{5'd0}};
                        in_data_reg[j] = in_data_reg[j] + i*{{5'd8},{5'd8},{5'd8},{5'd8},{5'd8},{5'd8},{5'd8},{5'd8}};
                    end
                end 
            end
        end else begin : GAUSS_AND_PULSE_RUN
            forever begin
                for(int i=0; i<64; i++) begin: FILL_DELAYED_PULSES
                    #0.01;
                    @(posedge clk);
                    for(int j=0; j<NCHAN; j=j+1) begin : CHANNEL_FILL_DELAYED_PULSES
                        for(int k=0; k<NSAMP; k=k+1) begin : SAMPLE_FILL_DELAYED_PULSES
                            do begin
                                stim_val = $dist_normal(seed, stim_mean, stim_sdev);
                            end while(stim_val > 31 || stim_val < 0); // Don't leave 5 bit range please
                            cycling_num = i*8+k - delay_array[ALIGNED_BEAM][j];
                            if((cycling_num) < 5 && (cycling_num) > 0) begin : ADD_PULSE
                                if(cycling_num%2 == 0) begin
                                    stim_val = stim_val + 8;
                                end else begin
                                    stim_val = stim_val - 8;
                                end
                                if(stim_val > 31) begin
                                    stim_val = 31;
                                end else if (stim_val < 0)begin
                                    stim_val = 0; // ~ 2.5 SNR
                                end
                            end
                            in_data_reg[j][k*5 +: 5] = stim_val;
                        end
                    end
                end
            end
        end
    end



    
endmodule
