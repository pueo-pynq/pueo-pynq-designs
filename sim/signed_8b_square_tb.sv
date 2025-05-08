`timescale 1ns / 1ps
`include "interfaces.vh"
module signed_8b_square_tb;

    // Clocks
    wire clk;
    tb_rclk #(.PERIOD(5.0)) u_clk(.clk(clk));

    wire [7:0]  in_val;
    wire [14:0] out_val;
    
    reg signed [7:0]    value = {8{1'b0}};
    reg  [14:0]         square;

    assign in_val = value;
    assign square = out_val;

    signed_8b_square u_squarer(
        .clk_i(clk),
        .in_i(in_val),       
        .out_o(out_val));

    // Test loop
    initial begin : VALLOOP
        $monitor("Testing Squares");
        $monitor($sformatf("(%1d)^2 = %1d", value, square));
        for(int j=0; j<25; j=j+1) begin
            #1.75;
            @(posedge clk);
        end
                    
        for(int i=0; i<256; i=i+1) begin
            @(posedge clk);
            #1.75;
            value = value+1;
        end 
    end



    
endmodule
