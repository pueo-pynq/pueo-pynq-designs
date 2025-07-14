module Gaussian12b_LFSR_v2 #(   parameter SEED_BASE=0 )
    (
    input clk,
    input rst_i,
    output [127:0] sim_data
    );

    // reg [7:0][11:0][15:0] value_sum;

    genvar samp_idx, stage_idx;
    generate
    
        for(samp_idx=0; samp_idx<8; samp_idx++) begin
            
           

            reg [16:0][15:0] add_connections = {17{16'h0000}};
            // reg [15:0] final_sum;
            for(stage_idx=0; stage_idx<16; stage_idx++) begin
                
                wire [7:0] LFSR_out;
                 LFSR #(.NUM_BITS(8)) LFSR_idx( .i_Clk(clk),
                                                .i_Enable(1'b1),
                                                .i_Seed_DV(rst_i),
                                                .i_Seed_Data(SEED_BASE+(samp_idx*16)+(stage_idx)),
                                                // .o_LFSR_Done(reset_dly[0]),
                                                .o_LFSR_Data(LFSR_out)
                                            );
                always @(posedge clk) begin
                    add_connections[stage_idx+1] = LFSR_out + add_connections[stage_idx];
                end
            end
            // always @(posedge clk) begin
            //     final_sum = add_connections[0] + add_connections[1];
            // end
            assign sim_data[(samp_idx*16) +: 16] = add_connections[16];
        end
    endgenerate
    

endmodule