`timescale 1ns / 1ps
`include "interfaces.vh"
module dual_pueo_beam_tb;

    localparam NBITS=5;
    localparam NSAMP=8; 
    localparam NCHAN=8;

    // Clocks
    wire clk;
    tb_rclk #(.PERIOD(5.0)) u_clk(.clk(clk));


    // vectorize inputs
    reg [NBITS-1:0] beamA_vec_reg [NCHAN-1:0][NSAMP-1:0];
    reg [NBITS-1:0] beamB_vec_reg [NCHAN-1:0][NSAMP-1:0];

    reg [17:0]  thresh_reg                  = 18'd0;
    reg [1:0]   thresh_ce_reg               = 2'b00;
    reg         update_reg                  = 1'b0;
    reg [1:0]   trigger_reg; 
    
    wire [17:0] thresh                      = thresh_reg;
    wire [1:0]  thresh_ce                   = thresh_ce_reg;
    wire        update                      = update_reg;
    wire [1:0]  trigger;

    assign trigger_reg = trigger;

    wire [NCHAN*NSAMP*NBITS-1:0] beamA;
    wire [NCHAN*NSAMP*NBITS-1:0] beamB;

    genvar chan_gen_idx, samp_gen_idx;
    generate
        for(chan_gen_idx=0; chan_gen_idx<NCHAN; chan_gen_idx++) begin
            for(samp_gen_idx=0; samp_gen_idx<NSAMP; samp_gen_idx++) begin
                assign beamA[NBITS*NSAMP*chan_gen_idx + NBITS*samp_gen_idx +: NBITS] = beamA_vec_reg[chan_gen_idx][samp_gen_idx];
                assign beamB[NBITS*NSAMP*chan_gen_idx + NBITS*samp_gen_idx +: NBITS] = beamB_vec_reg[chan_gen_idx][samp_gen_idx];
            end
        end
    endgenerate

    dual_pueo_beam u_beamform(
        .clk_i(clk),
        .beamA_i(beamA),
        .beamB_i(beamB),
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
        #1.75
        @(posedge clk);
        #1.75
        $display("Initial Threshold Load");
        update_reg = 1'b0;
        thresh_reg = 18'd256; //10
        thresh_ce_reg = 2'b10; // Load this threshold into A(?).
        @(posedge clk);
        thresh_reg = 18'd255;//h0F000; //20
        thresh_ce_reg = 2'b01; // Load this threshold into B(?).
        #1.75
        @(posedge clk);
        update_reg = 1'b1; // THIS ALSO MEANS IT TAKES 2 CLOCKS TO LOAD
        #1.75
        @(posedge clk);
        #1.75
        thresh_ce_reg = 2'b00;
        update_reg = 1'b0;
        @(posedge clk);
        #1.75
        $display("Initial Threshold Has Been Loaded");

        for(int chan_idx=0; chan_idx<NCHAN; chan_idx++) begin
            for(int samp_idx=0; samp_idx<NSAMP; samp_idx++) begin
                beamA_vec_reg[chan_idx][samp_idx] = 5'b0;
                beamB_vec_reg[chan_idx][samp_idx] = 5'b0;
            end
        end

        for(int i=0; i<4; i=i+1) begin
            
            for(int j=0; j<16;j=j+1) begin
                @(posedge clk);
                #1.75;
            end
            // $display($sformatf("All inputs %1d,\t Trigger [%1d,%1d]",beamA_in0_reg, trigger_reg[0], trigger_reg[1]));

            for(int chan_idx=0; chan_idx<NCHAN; chan_idx++) begin
                for(int samp_idx=0; samp_idx<NSAMP; samp_idx++) begin
                    beamA_vec_reg[chan_idx][samp_idx] = i*8 + samp_idx;
                    beamB_vec_reg[chan_idx][samp_idx] = i*8;
                end
            end

        end 
        for(int j=0; j<16;j=j+1) begin
            @(posedge clk);
            #1.75;
        end
        // $display($sformatf("All inputs %1d,\t Trigger [%1d,%1d]",beamA_in0_reg, trigger_reg[0], trigger_reg[1]));

        for(int chan_idx=0; chan_idx<NCHAN; chan_idx++) begin
            for(int samp_idx=0; samp_idx<NSAMP; samp_idx++) begin
                beamA_vec_reg[chan_idx][samp_idx] = 31;
                beamB_vec_reg[chan_idx][samp_idx] = 31;
            end
        end

        for(int j=0; j<16;j=j+1) begin
            @(posedge clk);
            #1.75;
        end
        // $display($sformatf("All inputs %1d,\t Trigger [%1d,%1d]",beamA_in0_reg, trigger_reg[0], trigger_reg[1]));

        for(int chan_idx=0; chan_idx<NCHAN; chan_idx++) begin
            for(int samp_idx=0; samp_idx<NSAMP; samp_idx++) begin
                if(samp_idx < NSAMP/2) begin
                    beamA_vec_reg[chan_idx][samp_idx] = 15;
                    beamB_vec_reg[chan_idx][samp_idx] = 16;
                end else begin
                    beamA_vec_reg[chan_idx][samp_idx] = 16;
                    beamB_vec_reg[chan_idx][samp_idx] = 15;

                end
            end
        end

        for(int j=0; j<16;j=j+1) begin
            @(posedge clk);
            #1.75;
        end
        // $display($sformatf("All inputs %1d,\t Trigger [%1d,%1d]",beamA_in0_reg, trigger_reg[0], trigger_reg[1]));

        for(int chan_idx=0; chan_idx<NCHAN; chan_idx++) begin
            for(int samp_idx=0; samp_idx<NSAMP; samp_idx++) begin
                if(samp_idx < NSAMP-1) begin
                    beamA_vec_reg[chan_idx][samp_idx] = 16;
                    beamB_vec_reg[chan_idx][samp_idx] = 16;
                end else begin
                    beamA_vec_reg[chan_idx][samp_idx] = 17;
                    beamB_vec_reg[chan_idx][samp_idx] = 17;

                end
            end
        end



        for(int j=0; j<4;j=j+1) begin
            @(posedge clk);
            #1.75;
        end

    end



    
endmodule
