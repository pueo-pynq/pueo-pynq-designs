`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////
// File downloaded from http://www.nandland.com
///////////////////////////////////////////////////////////////////////////////
// Description: Simple Testbench for LFSR.v.  Set c_NUM_BITS to different
// values to verify operation of LFSR
///////////////////////////////////////////////////////////////////////////////
module LFSR_TB ();
 
  parameter c_NUM_BITS = 3;

  wire r_Clk;      
  wire [c_NUM_BITS-1:0] w_LFSR_Data;
  wire w_LFSR_Done;
  tb_rclk #(.PERIOD(5.0)) u_aclk(.clk(r_Clk));


   
  LFSR #(.NUM_BITS(c_NUM_BITS)) LFSR_inst
         (.i_Clk(r_Clk),
          .i_Enable(1'b1),
          .i_Seed_DV(1'b0),
          .i_Seed_Data({c_NUM_BITS{1'b0}}), // Replication
          .o_LFSR_Data(w_LFSR_Data),
          .o_LFSR_Done(w_LFSR_Done)
          );
  
   
endmodule // LFSR_TB