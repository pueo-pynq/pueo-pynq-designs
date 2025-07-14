`timescale 1ns / 1ps
`include "interfaces.vh"
module signed_8b_square_tb;

    // Clocks
    wire clk;
    tb_rclk #(.PERIOD(5.0)) u_clk(.clk(clk));

    wire [7:0]  in_val;
    wire [14:0] out_val;
    
    // reg signed [7:0]    value = {8{1'b0}};
    reg  [14:0]         square;

    assign in_val = value_int;
    assign square = out_val;

    signed_8b_square u_squarer(
        .clk_i(clk),
        .in_i(in_val),       
        .out_o(out_val));

    // Test loop
    int value_int = 0;
    int value_delay = 0;
    initial begin : VALLOOP
        $display("Testing Squares");
        for(int j=0; j<25; j=j+1) begin
            #1.75;
            @(posedge clk);
        end
                    
        for(int i=0; i<257; i=i+1) begin
            @(posedge clk);
            if(square !== (value_delay)*(value_delay)) begin
                $display($sformatf("ERROR: (Value:%1d)^2 != Square:%1d",value_delay,square));
            end
            #1.75;
            value_delay = value_int;
            value_int = value_int+1;
            if(value_int == 128) begin
                value_int = -127;
            end
        end 
    end



    
endmodule
