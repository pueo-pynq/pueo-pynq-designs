`timescale 1ns / 1ps
`include "interfaces.vh"
module beam_alignment_tb;

    // Clocks
    wire clk;
    tb_rclk #(.PERIOD(5.0)) u_clk(.clk(clk));

    localparam NBEAMS = 46;

    reg [39:0]          in_data_reg [7:0]   = {{40{1'b0}}, {40{1'b0}}, {40{1'b0}}, {40{1'b0}}, {40{1'b0}}, {40{1'b0}}, {40{1'b0}}, {40{1'b0}}};
    reg [17:0]          thresh_reg          = 18'd0;
    reg [NBEAMS-1:0]    thresh_ce_reg       = 2'b00;
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
        #1.75
        @(posedge clk);
        #1.75
        $display("Initial Threshold Load");
        update_reg = 1'b0;
        thresh_reg = 18'h0a; //10
        thresh_ce_reg = 2'b10; // Load this threshold into A.
        @(posedge clk);
        thresh_reg = 18'h14; //20
        thresh_ce_reg = 2'b01; // Load this threshold into B.
        #1.75
        @(posedge clk);
        update_reg = 1'b1; // Apply new thresholds
        #1.75
        @(posedge clk);
        #1.75
        thresh_ce_reg = 2'b00;
        update_reg = 1'b0;
        @(posedge clk);
        #1.75
        $display("Initial Threshold Has Been Loaded");
        forever begin
            for(int i=0; i<4; i=i+1) begin  
                // for(int j=0; j<16;j=j+1) begin
                //     @(posedge clk);
                //     #1.75;
                // end
                @(posedge clk);
                #1.75;
                for(int k=0; k<8; k=k+1) begin : CHANNEL_FILL
                    in_data_reg[k] = {{5'd7},{5'd6},{5'd5},{5'd4},{5'd3},{5'd2},{5'd1},{5'd0}};
                    in_data_reg[k] = in_data_reg[k] + i*{{5'd8},{5'd8},{5'd8},{5'd8},{5'd8},{5'd8},{5'd8},{5'd8}};
                end
            end 
            // @(posedge clk);
            // #1.75;
        end
    
        // beamA_in0_reg   = 17'd0;
        // beamA_in1_reg   = 17'd0;
        // beamB_in0_reg   = 17'd0;
        // beamB_in1_reg   = 17'd0;//{6{1'b0}}

        // for(int j=0; j<4;j=j+1) begin
        //     @(posedge clk);
        //     #1.75;
        // end

        // $display("Edge Thresholds Load");
        // update_reg = 1'b0;
        // thresh_reg = {1,{17{1'b1}}}; //262143 0x3FFFF
        // thresh_ce_reg = 2'b10; // Load this threshold into A.
        // @(posedge clk);
        // thresh_reg = {0,{17{1'b0}}}; //0
        // thresh_ce_reg = 2'b01; // Load this threshold into B.
        // #1.75
        // @(posedge clk);
        // update_reg = 1'b1; // THIS ALSO MEANS IT TAKES 2 CLOCKS TO LOAD
        // #1.75
        // @(posedge clk);
        // #1.75
        // thresh_ce_reg = 2'b00;
        // update_reg = 1'b0;
        // @(posedge clk);
        // #1.75
        // $display("Edge Thresholds Have Been Loaded");

        // beamA_in0_reg   = 17'd65535; //{17{1'b1}};
        // beamA_in1_reg   = 17'd65535; //{17{1'b1}};
        // beamB_in0_reg   = 17'd0; //{17{1'b1}};
        // beamB_in1_reg   = 17'd0; //{17{1'b1}};
        
        // for(int j=0; j<10;j=j+1) begin
        //     @(posedge clk);
        //     #1.75;
        // end

        // beamA_in0_reg   = 17'd65536; //{17{1'b1}};
        // beamA_in1_reg   = 17'd65536; //{17{1'b1}};
        // beamB_in0_reg   = 17'd0; //{17{1'b1}};
        // beamB_in1_reg   = 17'd0; //{17{1'b1}};
        
        // for(int j=0; j<10;j=j+1) begin
        //     @(posedge clk);
        //     #1.75;
        // end

    end



    
endmodule
