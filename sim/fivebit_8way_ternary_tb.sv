`timescale 1ns / 1ps
`include "interfaces.vh"
module fivebit_8way_ternary_tb;

    // Clocks
    wire clk;
    tb_rclk #(.PERIOD(5.0)) u_clk(.clk(clk));

    wire [4:0]  in_vals [7:0];
    wire [7:0] out_val;
    
    reg  [14:0] sum;

    // Test loop values
    int value_ints [8]   = '{0,0,0,0,0,0,0,0};
    int value_delays [8] = '{0,0,0,0,0,0,0,0};

    assign in_vals[0] = value_ints[0];
    assign in_vals[1] = value_ints[1];
    assign in_vals[2] = value_ints[2];
    assign in_vals[3] = value_ints[3];
    assign in_vals[4] = value_ints[4];
    assign in_vals[5] = value_ints[5];
    assign in_vals[6] = value_ints[6];
    assign in_vals[7] = value_ints[7];
    assign sum = out_val;

    fivebit_8way_ternary u_adder(
        .clk_i(clk),
        .A(in_vals[0]),
        .B(in_vals[1]),
        .C(in_vals[2]),
        .D(in_vals[3]),
        .E(in_vals[4]),
        .F(in_vals[5]),
        .G(in_vals[6]),
        .H(in_vals[7]),
        .O(out_val)
    );


    initial begin : VALLOOP
        $display("Testing Sums");
        for(int j=0; j<25; j=j+1) begin
            #1.75;
            @(posedge clk);
        end
                    
        for(int i=0; i<31; i=i+1) begin
            @(posedge clk);
            #1.75;
            // if(square !== (value_delay)*(value_delay)) begin
            //     $display($sformatf("ERROR: (Value:%1d)^2 != Square:%1d",value_delay,square));
            // end
            for(int j=0; j<8; j = j+1) begin   
                value_delays[j] = value_ints[j];
                value_ints[j] = value_ints[j]+1;
            end


        end 
    end



    
endmodule
