`timescale 1ns / 1ps
`include "interfaces.vh"

`define DLYFF #0.1

module L1_trigger_wrapper #(parameter NBEAMS=2, parameter AGC_TIMESCALE_REDUCTION_BITS = 2,
                    parameter WBCLKTYPE = "PSCLK", parameter CLKTYPE = "ACLK",
                    parameter TRIGGER_CLOCKS=375000000,
                    parameter HOLDOFF_CLOCKS=16,
                    parameter STARTING_TARGET=100)( // at 375 MHz this will count for 1 s  

        input wb_clk_i,
        input wb_rst_i,

        `TARGET_NAMED_PORTS_WB_IF( wb_ , 22, 32 ), // Address width, data width.
        input reset_i, 
        input aclk,
        input [7:0][95:0] dat_i,
        
        output [NBEAMS-1:0] trigger_o
    );

    `define ADDR_MATCH( addr, val, mask ) ( ( addr & mask ) == (val & mask) )
    localparam [9:0] THRESHOLD_MASK = {10{1'b1}};
    localparam NBITS_KP = 32;
    localparam NFRAC_KP = 10;

    // Pass commands not about trigger rate control loop down
    `DEFINE_WB_IF( L1_submodule_ , 22, 32);

    // //  Top interface target (S)        Connection interface (M)
    assign wb_ack_o = (wb_adr_i[14]) ? L1_submodule_ack_i : (state == ACK);
    assign wb_err_o = (wb_adr_i[14]) ? L1_submodule_err_i : 1'b0;
    assign wb_rty_o = (wb_adr_i[14]) ? L1_submodule_rty_i : 1'b0;
    assign wb_dat_o = (wb_adr_i[14]) ? L1_submodule_dat_i : response_reg;
    
    wire wb_control_loop_cyc_i;

    assign L1_submodule_cyc_o = wb_cyc_i && !wb_adr_i[14];
    assign wb_control_loop_cyc_i = wb_cyc_i && wb_adr_i[14];
    assign L1_submodule_stb_o = wb_stb_i;
    assign wb_control_loop_stb_o = wb_stb_i;
    assign L1_submodule_adr_o = wb_adr_i;
    assign wb_control_loop_adr_o = wb_adr_i;
    assign L1_submodule_dat_o = wb_dat_i;
    assign wb_control_loop_dat_o = wb_dat_i;
    assign L1_submodule_we_o = wb_we_i;
    assign wb_control_loop_we_o = wb_we_i;
    assign L1_submodule_sel_o = wb_sel_i;
    assign wb_control_loop_sel_o = wb_sel_i;


    // State machine control
    localparam FSM_BITS = 3;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] WRITE = 1;
    localparam [FSM_BITS-1:0] READ = 2;
    localparam [FSM_BITS-1:0] DELAY = 3;
    localparam [FSM_BITS-1:0] ACK = 4;
    reg [FSM_BITS-1:0] state = IDLE;    

   
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] response_reg = 31'h0; // Pass back trigger count information

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] trigger_count_wb_reg; // Pass back # of triggers on WB

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] trigger_threshold_wb_reg; // Pass back threshold value on WB

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [NBITS_KP-1:0] trigger_control_K_P; // P Parameter for control loop. 
                                            // This is the fraction of error value to change threshold by.


    // TODO Plan:   Use two state machines, one for this module's communication
    //              and one for managing the thresholds/rates. Both can be on the WB clock  
    //              since this is slow control.
    // Note: Completely unimplemented below this point
    // Note Note: Need to check whether this additional layer hurts timing. Don't expect so.

    ////////////////////////////////////////////////////////
    //////        Wishbone FSM stolen from AGC        //////
    ////////////////////////////////////////////////////////

    (* CUSTOM_CC_SRC = WBCLKTYPE *) // Store the thresholds here
    reg [NBEAMS-1:0][17:0] threshold_regs = {NBEAMS{18{1'b0}}};

    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [17:0] threshold_writing = {18{1'b0}};

    reg  [NBEAMS-1:0] trigger_threshold_ce = {NBEAMS{1'b0}};
    reg  [NBEAMS-1:0] trigger_threshold_ce_delayed = {NBEAMS{1'b0}};
    wire [NBEAMS-1:0] trigger_threshold_ce_aclk;


    // Update all thresholds
    reg trigger_threshold_update = 0;
    wire trigger_threshold_update_aclk;
    flag_sync u_update_flag(.in_clkA(trigger_threshold_update),.clkA(wb_clk_i),
                            .out_clkB(trigger_threshold_update_aclk),.clkB(aclk));

    // Request trigger count
    reg req_trigger_count = 0;
    wire trigger_count_aclk;
    flag_sync u_tick_flag(.in_clkA(req_trigger_count),.clkA(wb_clk_i),
                          .out_clkB(trigger_count_aclk),.clkB(aclk));

    // Mark the trigger count as completed
    reg  trigger_count_done = 0;
    wire trigger_count_done_aclk;
    wire trigger_count_done_wbclk;
    flag_sync u_done_flag(.in_clkA(trigger_count_done_aclk),.clkA(aclk),
                          .out_clkB(trigger_count_done_wbclk),.clkB(wb_clk_i));



    // Trigger rate sampling period control
    reg trigger_count_ce = 0; // Clock enable for counting out the 375 MHz clock
    wire trigger_time_done; // Signal that the trigger counting period is over
    always @(posedge aclk) begin
        if (trigger_count_aclk) trigger_count_ce <= 1'b1; // If you see a flag to start, enable clock
        else if (trigger_time_done) trigger_count_ce <= 1'b0; // If the period is over, stop counting
    end        
    // Move trigger_time_done to trigger_count_done_aclk, with a delay of 6 aclks
    reg [5:0] trigger_done_delay = {6{1'b0}};
    always @(posedge aclk) trigger_done_delay <= { trigger_done_delay[4:0], trigger_time_done };
    assign trigger_count_done_aclk = trigger_done_delay[5];

    // This is where we will count out the clocks in our trigger sampling period (shared by all beams) 
    dsp_counter_terminal_count #(.FIXED_TCOUNT("TRUE"),
                                .FIXED_TCOUNT_VALUE(TRIGGER_CLOCKS),
                                .HALT_AT_TCOUNT("TRUE"))
        u_trigger_timer(.clk_i(aclk),
                        .rst_i(trigger_count_aclk), // Reset the counter with new request flag
                        .count_i(trigger_count_ce),
                        .tcount_reached_o(trigger_time_done));


    genvar beam_idx;
    generate
        for(beam_idx=0; beam_idx<NBEAMS; beam_idx++) begin : CE_FLAGS_AND_THRESHOLD  
            // Flag to clock enable for a specific beam threshold load in
            flag_sync u_CE_flag(.in_clkA(trigger_threshold_ce_delayed[beam_idx]),.clkA(wb_clk_i),
                                .out_clkB(trigger_threshold_ce_aclk[beam_idx]),.clkB(aclk));     

            // Increment the counter if there is a trigger and not in holdoff
            always @(posedge aclk) begin
                
                if(trigger_count_aclk) begin // Reset for a new count
                    trigger_count_reg[beam_idx] <= 0;
                    holdoff_delay[beam_idx] <= 0; // reset the holdoff
                end else if(trigger_count_ce && trigger_signal_bit_o[beam_idx] && (holdoff_delay[beam_idx]==0)) begin
                    trigger_count_reg[beam_idx] <= trigger_count_reg[beam_idx] + 1;
                    holdoff_delay[beam_idx] <= HOLDOFF_CLOCKS; // Begin the holdoff
                end else if(holdoff_delay[beam_idx]>0) begin
                    holdoff_delay[beam_idx] <= holdoff_delay[beam_idx] - 1; // Count down from last trigger count
                end
            end

            // Stage a threshold in for a specific beam
            always @(posedge wb_clk_i) begin
                if((state == IDLE) && (wb_threshold_cyc_i && wb_stb_i && `ADDR_MATCH( wb_adr_i,  10'h200 + beam_idx, THRESHOLD_MASK ) && wb_we_i && wb_sel_i[1] && wb_dat_i[0]))
                begin
                    trigger_threshold_ce[beam_idx] <= 1'b1;
                    threshold_writing <= threshold_regs[beam_idx];
                end else begin
                    trigger_threshold_ce[beam_idx] <= 1'b0;
                end
            end
        end
    endgenerate

    always @(posedge wb_clk_i) begin
        if (req_trigger_count) trigger_count_done <= 0;
        else if (trigger_count_done_wbclk) trigger_count_done <= 1;
        
        if (trigger_count_done_wbclk) begin // flag that a counting cycle just completed
            trigger_count_wb_reg <= trigger_count_out; // Contains all results
        end            

        // Write command flags. These handle writes to address 0x00.
        req_trigger_count <= (state == IDLE) && (wb_threshold_cyc_i && wb_stb_i && `ADDR_MATCH( wb_adr_i, 10'h000, THRESHOLD_MASK ) && wb_we_i && wb_sel_i[0] && wb_dat_i[0]);
        trigger_threshold_update <= (state == IDLE) && (wb_threshold_cyc_i && wb_stb_i && `ADDR_MATCH( wb_adr_i, 10'h000, THRESHOLD_MASK ) && wb_we_i && wb_sel_i[1] && wb_dat_i[1]);
        // Give an extra clock to make sure threshold_writing sets up
        trigger_threshold_ce_delayed <= trigger_threshold_ce;
        
        // Determine what we are doing this cycle
        case (state)
            IDLE: if (wb_threshold_cyc_i && wb_stb_i) begin
                if (wb_we_i) state <= WRITE;
                else state <= READ;
            end
            WRITE: state <= DELAY; // The delay is to let the the delayed threshold_CE complete the clock crossing
            DELAY: state <= ACK;
            READ: state <= ACK;
            ACK: state <= IDLE;
            default: state <= IDLE; // Should never go here, but there arae more bits than states
        endcase
        
        // If reading, load the response in
        if (state == READ) begin
            if(wb_adr_i[8]) response_reg <= trigger_count_wb_reg[wb_adr_i[7:0]];
            else response_reg = trigger_count_done;
        end
        // If writing to a threshold, put it in the appropriate register
        if (state == WRITE) begin
            if (wb_adr_i[8]) begin // The 8th bit is used to indicate a threshold write
                if (wb_sel_i[0]) threshold_regs[wb_adr_i[7:0]][7:0] <= wb_dat_i[7:0];
                if (wb_sel_i[1]) threshold_regs[wb_adr_i[7:0]][15:8] <= wb_dat_i[15:8];
                if (wb_sel_i[2]) threshold_regs[wb_adr_i[7:0]][17:16] <= wb_dat_i[17:16];
            end             
        end
    end

    assign trigger_count_out = trigger_count_reg;

    wire  [7:0][39:0] data_stage_connection;

    // trigger_chain_x8_wrapper #(.AGC_TIMESCALE_REDUCTION_BITS(AGC_TIMESCALE_REDUCTION_BITS))
    //             u_chain(
    //                 .wb_clk_i(wb_clk_i),
    //                 .wb_rst_i(wb_rst_i),
    //                 // `CONNECT_WBS_IFS( wb_bq_ , wb_bq_ ),//L
    //                 // `CONNECT_WBS_IFS( wb_agc_ , wb_agc_ ),
    //                 `CONNECT_WBS_IFM( wb_bq_ , bq_submodule_ ),//L
    //                 `CONNECT_WBS_IFM( wb_agc_ , agc_submodule_ ),
    //                 .reset_i(reset_i), 
    //                 .aclk(aclk),
    //                 .dat_i(dat_i),
    //                 .dat_o(data_stage_connection));

    // //TODO: Add holdoff at this stage!
    // assign trigger_o = trigger_signal_bit_o;

    // beamform_trigger #(.NBEAMS(NBEAMS)) 
    //     u_trigger(
    //         .clk_i(aclk),
    //         .data_i(data_stage_connection),

    //         .thresh_i(threshold_writing),
    //         .thresh_ce_i(trigger_threshold_ce_aclk),
    //         .update_i(trigger_threshold_update_aclk),        
            
    //         .trigger_o(trigger_signal_bit_o));



endmodule
