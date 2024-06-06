`timescale 1ns / 1ps
`include "interfaces.vh"
module agc_design(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 22, 32 ),
        input aclk,
        input aresetn,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc0_ , 128 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc1_ , 128 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc2_ , 128 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc3_ , 128 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc4_ , 128 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc5_ , 128 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc6_ , 128 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( adc7_ , 128 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf0_ , 128 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf1_ , 128 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf2_ , 128 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( buf3_ , 128 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( dac0_ , 128 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( dac1_ , 128 )
    );
    
    parameter WBCLKTYPE = "PSCLK";
    parameter CLKTYPE = "ACLK";
    
    // Outputs of the AGC core
    wire [20:0] gt_accum_out;
    wire [20:0] lt_accum_out;
    wire [23:0] sq_accum_out;
    
    // Capture of square, gt, lt accumulators. These are wb-clk land
    // AGC tick is delayed for capture.
    (* CUSTOM_CC_SRC = CLKTYPE *)
    reg [20:0] gt_accum_reg = {21{1'b0}};
    (* CUSTOM_CC_SRC = CLKTYPE *)
    reg [20:0] lt_accum_reg = {21{1'b0}};
    (* CUSTOM_CC_SRC = CLKTYPE *)
    reg [23:0] sq_accum_reg = {24{1'b0}};
    
    // agc scale
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [16:0] agc_scale = {17{1'b0}};
    // offset
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [7:0] agc_offset = {8{1'b0}};
    // load agc scale
    reg agc_scale_load = 0;
    wire agc_scale_load_aclk;
    // flaggy flaggy
    flag_sync u_scale_flag(.in_clkA(agc_scale_load),.clkA(wb_clk_i),
                           .out_clkB(agc_scale_load_aclk),.clkB(aclk));

    // load agc offset
    reg agc_offset_load = 0;
    wire agc_offset_load_aclk;
    flag_sync u_offset_flag(.in_clkA(agc_offset_load),.clkA(wb_clk_i),
                            .out_clkB(agc_offset_load_aclk),.clkB(aclk));

    // apply both
    reg agc_apply = 0;
    wire agc_apply_aclk;
    flag_sync u_apply_flag(.in_clkA(agc_apply),.clkA(wb_clk_i),
                           .out_clkB(agc_apply_aclk),.clkB(aclk));
    
    reg req_agc_tick = 0;
    wire agc_tick_aclk;
    flag_sync u_tick_flag(.in_clkA(req_agc_tick),.clkA(wb_clk_i),
                          .out_clkB(agc_tick_aclk),.clkB(aclk));


    reg agc_done = 0;
    wire agc_done_aclk;
    wire agc_done_wbclk;
    flag_sync u_done_flag(.in_clkA(agc_done_aclk),.clkA(aclk),
                          .out_clkB(agc_done_wbclk),.clkB(wb_clk_i));
    reg agc_reset = 0;
    wire agc_reset_aclk;
    flag_sync u_reset_flag(.in_clkA(agc_reset),.clkA(wb_clk_i),
                           .out_clkB(agc_reset_aclk),.clkB(aclk));
                           
    `define ADDR_MATCH( addr, val, mask ) ( ( addr & mask ) == (val & mask) )

    // pick off bits [4:2]
    localparam [21:0] AGC_MASK = 22'h00001C;
    
    wire [31:0] register_data[7:0];
    // BIT 0 = agc_tick
    // BIT 1 = agc complete
    // BIT 2 = agc reset
    // BIT 8 = load scale
    // BIT 9 = load offset
    // BIT 10 = apply
    assign register_data[0] = {{30{1'b0}},agc_done,1'b0};
    assign register_data[1] = { {8{1'b0}},sq_accum_reg };
    assign register_data[2] = { {11{1'b0}},gt_accum_reg };
    assign register_data[3] = { {11{1'b0}},lt_accum_reg };
    assign register_data[4] = { {15{1'b0}},agc_scale };
    assign register_data[5] = { {8{1'b0}},agc_offset };
    assign register_data[6] = register_data[2]; // shadow to ease decode
    assign register_data[7] = register_data[3]; // shadow to ease decode

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] register_hold = {32{1'b0}};

    localparam FSM_BITS = 2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] WRITE = 1;
    localparam [FSM_BITS-1:0] READ = 2;
    localparam [FSM_BITS-1:0] ACK = 3;
    reg [FSM_BITS-1:0] state = IDLE;    
        
    always @(posedge wb_clk_i) begin
        if (req_agc_tick) agc_done <= 0;
        else if (agc_done_wbclk) agc_done <= 1;
        
        if (agc_done_wbclk) begin
            gt_accum_reg <= gt_accum_out;
            lt_accum_reg <= lt_accum_out;
            sq_accum_reg <= sq_accum_out;
        end            

        req_agc_tick <= (state == IDLE) && (wb_cyc_i && wb_stb_i && `ADDR_MATCH( wb_adr_i, 22'h0, AGC_MASK ) && wb_we_i && wb_sel_i[0] && wb_dat_i[0]);
        agc_reset <= (state == IDLE) && (wb_cyc_i && wb_stb_i && `ADDR_MATCH( wb_adr_i, 22'h0, AGC_MASK ) && wb_we_i && wb_sel_i[0] && wb_dat_i[2]);
        agc_scale_load <= (state == IDLE) && (wb_cyc_i && wb_stb_i && `ADDR_MATCH( wb_adr_i, 22'h0, AGC_MASK ) && wb_we_i && wb_sel_i[1] && wb_dat_i[8]);
        agc_offset_load <= (state == IDLE) && (wb_cyc_i && wb_stb_i && `ADDR_MATCH( wb_adr_i, 22'h0, AGC_MASK ) && wb_we_i && wb_sel_i[1] && wb_dat_i[9]);
        agc_apply <= (state == IDLE) && (wb_cyc_i && wb_stb_i && `ADDR_MATCH( wb_adr_i, 22'h0, AGC_MASK ) && wb_we_i && wb_sel_i[1] && wb_dat_i[10]);
    
        // THIS IS SO DUMB I DON'T REALLY NEED TO WAIT
        case (state)
            IDLE: if (wb_cyc_i && wb_stb_i) begin
                if (wb_we_i) state <= WRITE;
                else state <= READ;
            end
            WRITE: state <= ACK;
            READ: state <= ACK;
            ACK: state <= IDLE;
        endcase
        
        // WHATEVER
        if (state == READ) register_hold <= register_data[wb_adr_i[3:2]];
        // SO DUMB
        if (state == WRITE) begin
            if (`ADDR_MATCH(wb_adr_i, 22'h10, AGC_MASK)) begin
                if (wb_sel_i[0]) agc_scale[7:0] <= wb_dat_i[7:0];
                if (wb_sel_i[1]) agc_scale[15:8] <= wb_dat_i[15:8];
                if (wb_sel_i[2]) agc_scale[16] <= wb_dat_i[16];
            end
            if (`ADDR_MATCH(wb_adr_i, 22'h14, AGC_MASK)) begin
                if (wb_sel_i[0]) agc_offset <= wb_dat_i[7:0];
            end                
        end
    end

    // UNPACK is 128 -> 96
    function [95:0] unpack;
        input [127:0] data_in;
        integer i;
        begin
            for (i=0;i<8;i=i+1) begin
                unpack[12*i +: 12] = data_in[(16*i+4) +: 12];
            end
        end
    endfunction
    // PACK5 is 5 -> 128 - WE SCALE UP BY 16 FOR VISIBILITY!!
    function [127:0] pack5;
        input [39:0] data_in;
        integer i;
        begin
            for (i=0;i<8;i=i+1) begin
                pack5[(16*i+13) +: 3] = {3{1'b0}};
                pack5[(16*i+8) +: 5] = data_in[5*i +: 5];
                pack5[(16*i) +: 8] = {8{1'b0}};
            end
        end
    endfunction    

    // THIS IS OUR TIMER
    // RUN FOR 131072 CLOCKS I THINK THIS WORKS
    reg agc_ce = 0;
    wire agc_time_done;
    always @(posedge aclk) begin
        if (agc_tick_aclk) agc_ce <= 1'b1;
        else if (agc_time_done) agc_ce <= 1'b0;
    end        
    reg [5:0] agc_done_delay = {6{1'b0}};
    always @(posedge aclk) agc_done_delay <= { agc_done_delay[4:0], agc_time_done };
    assign agc_done_aclk = agc_done_delay[5];
    dsp_counter_terminal_count #(.FIXED_TCOUNT("TRUE"),
                                 .FIXED_TCOUNT_VALUE(131072),
                                 .HALT_AT_TCOUNT("TRUE"))
            u_agc_timer(.clk_i(aclk),
                        .rst_i(agc_tick_aclk),
                        .count_i(agc_ce),
                        .tcount_reached_o(agc_time_done));
    // SCREW WITH ONE GUY ONLY
    wire [39:0] agc_out;
    agc_core #(.CLKTYPE(CLKTYPE)) u_agc0( .clk_i(aclk),
                     .rf_dat_i(unpack(adc0_tdata)),
                     .rf_dat_o(agc_out),
                     .sq_accum_o(sq_accum_out),
                     .gt_accum_o(gt_accum_out),
                     .lt_accum_o(lt_accum_out),
                     
                     .agc_tick_i(agc_tick_aclk),
                     .agc_ce_i(agc_ce),
                     .agc_rst_i(agc_reset_aclk),
                     .agc_scale_i( agc_scale ),
                     .offset_i( agc_offset ),
                     .agc_scale_ce_i( agc_scale_load_aclk ),
                     .agc_offset_ce_i(agc_offset_load_aclk),
                     .agc_apply_i(agc_apply_aclk));

    assign buf0_tdata = pack5( agc_out );
    assign buf0_tvalid = 1'b1;
    assign buf1_tdata = adc0_tdata;
    assign buf1_tvalid = 1'b1;
    assign dac0_tdata = pack5( agc_out );
    assign dac0_tvalid = 1'b1;
    assign dac1_tdata = adc0_tdata;
    assign dac1_tvalid = 1'b1;    
    
    assign wb_ack_o = (state == ACK);
    assign wb_dat_o = register_hold;
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;

endmodule
