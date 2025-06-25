`timescale 1ns / 1ps

module Gaussian12b_LFSR_v2_tb ();
 
  parameter c_NUM_BITS = 3;

  wire r_Clk;      
  tb_rclk #(.PERIOD(5.0)) u_aclk(.clk(r_Clk));
  reg rst = 0;
  reg [127:0] sim_data_reg;

    // input clk,
    // output [127:0] sim_data

    initial begin
      rst=0;
      @(posedge r_Clk)
      rst=1;
      @(posedge r_Clk)
      rst=0;
    end
   
  Gaussian12b_LFSR_v2 #(.SEED_BASE(48'b0)) G_LFSR_inst
         (.clk(r_Clk),
          .rst_i(rst),
          .sim_data(sim_data_reg)
          );
  
   
endmodule