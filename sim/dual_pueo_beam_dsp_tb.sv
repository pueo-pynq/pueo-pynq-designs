`timescale 1ns / 1ps
`include "interfaces.vh"
module dual_pueo_beam_dsp_tb;

    // Clocks
    wire clk;
    tb_rclk #(.PERIOD(5.0)) u_clk(.clk(clk));


    reg [16:0]  beamA_in0_reg   = 17'd0;
    reg [16:0]  beamA_in1_reg   = 17'd0;
    reg [16:0]  beamB_in0_reg   = 17'd0;
    reg [16:0]  beamB_in1_reg   = 17'd0;
    reg [17:0]  thresh_reg      = 18'd0;
    reg [1:0]   thresh_ce_reg   = 2'b00;
    reg         update_reg      = 1'b0;
    reg [1:0]   trigger_reg; 

    wire [16:0] beamA_in0       = beamA_in0_reg;
    wire [16:0] beamA_in1       = beamA_in1_reg;
    wire [16:0] beamB_in0       = beamB_in0_reg;
    wire [16:0] beamB_in1       = beamB_in1_reg;
    wire [17:0] thresh          = thresh_reg;
    wire [1:0]  thresh_ce       = thresh_ce_reg;
    wire        update          = update_reg;
    wire [1:0]  trigger;

    assign trigger_reg = trigger;

    // // Test loop values
    // int value_ints [8]   = '{0,0,0,0,0,0,0,0};
    // int value_delays [8] = '{0,0,0,0,0,0,0,0};


    dual_pueo_beam_dsp u_beam_dsp(
        .clk_i(clk),
        .beamA_in0_i(beamA_in0),
        .beamA_in1_i(beamA_in1),
        .beamB_in0_i(beamB_in0),
        .beamB_in1_i(beamB_in1),
        
        .thresh_i(thresh),
        .thresh_ce_i(thresh_ce),
        .update_i(update), // This may be redundant
        
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
        thresh_ce_reg = 2'b10; // Load this threshold into A(?).
        @(posedge clk);
        thresh_reg = 18'h14; //20
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
                    
        for(int i=0; i<31; i=i+1) begin
            
            for(int j=0; j<16;j=j+1) begin
                @(posedge clk);
                #1.75;
            end
            $display($sformatf("All inputs %1d,\t Trigger [%1d,%1d]",beamA_in0_reg, trigger_reg[0], trigger_reg[1]));

            beamA_in0_reg = beamA_in0_reg + 1;
            beamA_in1_reg = beamA_in1_reg + 1;
            beamB_in0_reg = beamB_in0_reg + 1;
            beamB_in1_reg = beamB_in1_reg + 1;

        end 
        @(posedge clk);
        #1.75;
    
        beamA_in0_reg   = 17'd0;
        beamA_in1_reg   = 17'd0;
        beamB_in0_reg   = 17'd0;
        beamB_in1_reg   = 17'd0;//{6{1'b0}}

        for(int j=0; j<4;j=j+1) begin
            @(posedge clk);
            #1.75;
        end

        $display("Edge Thresholds Load");
        update_reg = 1'b0;
        thresh_reg = {1,{17{1'b1}}}; //262143 0x3FFFF
        thresh_ce_reg = 2'b10; // Load this threshold into A(?).
        @(posedge clk);
        thresh_reg = {0,{17{1'b0}}}; //0
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
        $display("Edge Thresholds Have Been Loaded");

        beamA_in0_reg   = 17'd65535; //{17{1'b1}};
        beamA_in1_reg   = 17'd65535; //{17{1'b1}};
        beamB_in0_reg   = 17'd65535; //{17{1'b1}};
        beamB_in1_reg   = 17'd65535; //{17{1'b1}};
        
        for(int j=0; j<10;j=j+1) begin
            @(posedge clk);
            #1.75;
        end

        beamA_in0_reg   = 17'd65536; //{17{1'b1}};
        beamA_in1_reg   = 17'd65536; //{17{1'b1}};
        beamB_in0_reg   = 17'd65536; //{17{1'b1}};
        beamB_in1_reg   = 17'd65536; //{17{1'b1}};
        
        for(int j=0; j<10;j=j+1) begin
            @(posedge clk);
            #1.75;
        end

    end



    
endmodule
