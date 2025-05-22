`timescale 1ns / 1ps
`include "interfaces.vh"

`define DLYFF #0.1
// Pre-trigger filter chain.
// 1) Shannon-Whitaker low pass filter
// 2) Two Biquads in serial (to be used as notches)
// 3) AGC and 12->5 bit conversion
module L1_trigger #(parameter NBEAMS=2, parameter AGC_TIMESCALE_REDUCTION_BITS = 2, parameter WBCLKTYPE = "PSCLK", parameter CLKTYPE = "ACLK")(  

        input wb_clk_i,
        input wb_rst_i,

        // One wishbone interface to control both AGC and Biquads
        // Bit 12 differentiates between the two (0 for AGC, 1 for BQs)
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 22, 32 ), // Address width, data width.

        // // Wishbone stuff for writing in coefficients to the biquads
        // `TARGET_NAMED_PORTS_WB_IF( wb_bq_ , 22, 32 ), // Address width, data width. 

        // // Wishbone stuff for writing to the AGC
        // `TARGET_NAMED_PORTS_WB_IF( wb_agc_ , 22, 32 ), // Address width, data width.

        // // Beam Thresholds
        // input [17:0] thresh_i,
        // input [NBEAMS-1:0] thresh_ce_i,
        // input update_i,    
        
        // Control to capture the output to the RAM buffer
        input reset_i, 
        input aclk,
        input [7:0][95:0] dat_i,
        
        output [NBEAMS-1:0] trigger_o
    );

    `define ADDR_MATCH( addr, val, mask ) ( ( addr & mask ) == (val & mask) )
    localparam [9:0] THRESHOLD_MASK = {10{1'b1}};

    // State machine control
    localparam FSM_BITS = 3;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] WRITE = 1;
    localparam [FSM_BITS-1:0] READ = 2;
    localparam [FSM_BITS-1:0] DELAY = 3;
    localparam [FSM_BITS-1:0] ACK = 4;
    reg [FSM_BITS-1:0] state = IDLE;    

    wire[NBEAMS-1:0][31:0] trigger_count_out;

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] response_reg = 31'h0; // Pass back # of triggers on WB

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [NBEAMS-1:0][31:0] trigger_count_reg; // Pass back # of triggers on WB

    // (* CUSTOM_CC_DST = WBCLKTYPE *)
    // reg thresh_ack_reg = 1'b0;

    // (* CUSTOM_CC_DST = WBCLKTYPE *)
    // reg thresh_err_reg = 1'b0;

    // (* CUSTOM_CC_DST = WBCLKTYPE *)
    // reg thresh_rty_reg = 1'b0;


    // Wishbone connection split between AGC, Biquads, and Trigger Rate
    // Use bits 13 and 12 to differentiate, 00 for AGC, 01 for Biquad, 10 for Trigger Rate
    // These interfaces are host-named (M). Sine the ports of this module are target-named,
    // there needs to be crossover
    `DEFINE_WB_IF( agc_submodule_ , 22, 32);
    `DEFINE_WB_IF( bq_submodule_ , 22, 32);

    reg wb_ack_o_reg = (state == ACK);
    reg wb_err_o_reg = 1'b0;
    reg wb_rty_o_reg = 1'b0;
    reg [31:0] wb_dat_o_reg = response_reg;

    assign wb_ack_o = wb_ack_o_reg;
    assign wb_err_o = wb_err_o_reg;
    assign wb_rty_o = wb_rty_o_reg;
    assign wb_dat_o = wb_dat_o_reg;

    always @(*) begin // Maybe could change to just wb_adr_i, could test this later
    // always @(posedge wb_clk_i) begin // Maybe could change to just wb_adr_i, could test this later
        case(wb_adr_i[13:12])
            2'b00: begin // Control AGC
                wb_ack_o_reg =  `DLYFF agc_submodule_ack_i;
                wb_err_o_reg =  `DLYFF agc_submodule_err_i;
                wb_rty_o_reg =  `DLYFF agc_submodule_rty_i;
                wb_dat_o_reg =  `DLYFF agc_submodule_dat_i;
            end
            2'b01: begin // Control BQ
                wb_ack_o_reg =  `DLYFF bq_submodule_ack_i;
                wb_err_o_reg =  `DLYFF bq_submodule_err_i;
                wb_rty_o_reg =  `DLYFF bq_submodule_rty_i;
                wb_dat_o_reg =  `DLYFF bq_submodule_dat_i;
            end
            default: begin // Control Trigger Threshold
                wb_ack_o_reg =  `DLYFF (state == ACK);
                wb_err_o_reg =  `DLYFF 1'b0;
                wb_rty_o_reg =  `DLYFF 1'b0;
                wb_dat_o_reg =  `DLYFF response_reg;
            end
        endcase
    end

    // These are replaced with the case statement above
    // //  Top interface target (S)        Connection interface (M)
    // assign wb_ack_o = (wb_adr_i[12]) ? bq_submodule_ack_i : agc_submodule_ack_i;
    // assign wb_err_o = (wb_adr_i[12]) ? bq_submodule_err_i : agc_submodule_err_i;
    // assign wb_rty_o = (wb_adr_i[12]) ? bq_submodule_rty_i : agc_submodule_rty_i;
    // assign wb_dat_o = (wb_adr_i[12]) ? bq_submodule_dat_i : agc_submodule_dat_i;
    
    wire wb_threshold_cyc_i;

    // FIX the acks here to prevent simulation time slipping from delaying de-assertion (BAD)
    assign agc_submodule_cyc_o = wb_cyc_i && !wb_adr_i[12] && !wb_adr_i[13];
    assign bq_submodule_cyc_o = wb_cyc_i && wb_adr_i[12] && !wb_adr_i[13];
    
    assign wb_threshold_cyc_i = wb_cyc_i && wb_adr_i[13];
    assign agc_submodule_stb_o = wb_stb_i;
    assign bq_submodule_stb_o = wb_stb_i;
    assign agc_submodule_adr_o = wb_adr_i;
    assign bq_submodule_adr_o = wb_adr_i;
    assign agc_submodule_dat_o = wb_dat_i;
    assign bq_submodule_dat_o = wb_dat_i;
    assign agc_submodule_we_o = wb_we_i;
    assign bq_submodule_we_o = wb_we_i;
    assign agc_submodule_sel_o = wb_sel_i;
    assign bq_submodule_sel_o = wb_sel_i;


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

    genvar i;
    generate
        for(i=0; i<NBEAMS; i++) begin
            flag_sync u_CE_flag(.in_clkA(trigger_threshold_ce_delayed[i]),.clkA(wb_clk_i),
                                .out_clkB(trigger_threshold_ce_aclk[i]),.clkB(aclk));
        end
    endgenerate

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

    genvar beam_idx;
    generate
        for(beam_idx=0; beam_idx<NBEAMS; beam_idx++) begin : CE_FLAGS_AND_THRESHOLD                      
            always @(posedge wb_clk_i) begin
                if((state == IDLE) && (wb_threshold_cyc_i && wb_stb_i && `ADDR_MATCH( wb_adr_i,  10'h200 + beam_idx, THRESHOLD_MASK ) && wb_we_i && wb_sel_i[1] && wb_dat_i[0]))
                begin
                    trigger_threshold_ce[beam_idx] <= 1'b1;
                    threshold_writing <= threshold_regs;
                end
            end
        end
    endgenerate

    always @(posedge wb_clk_i) begin
        if (req_trigger_count) trigger_count_done <= 0;
        else if (trigger_count_done_wbclk) trigger_count_done <= 1;
        
        if (trigger_count_done_wbclk) begin
            trigger_count_reg <= trigger_count_out;
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
            if(wb_adr_i[8]) response_reg <= trigger_count_reg[wb_adr_i[7:0]];
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

    // TODO: WILL WANT TO PUT SOME TRIGGER TIMERS IN HERE
    assign trigger_count_out = {NBEAMS{32'd100}};

    wire  [7:0][39:0] data_stage_connection;

    trigger_chain_x8_wrapper #(.AGC_TIMESCALE_REDUCTION_BITS(AGC_TIMESCALE_REDUCTION_BITS))
                u_chain(
                    .wb_clk_i(wb_clk_i),
                    .wb_rst_i(wb_rst_i),
                    // `CONNECT_WBS_IFS( wb_bq_ , wb_bq_ ),//L
                    // `CONNECT_WBS_IFS( wb_agc_ , wb_agc_ ),
                    `CONNECT_WBS_IFM( wb_bq_ , bq_submodule_ ),//L
                    `CONNECT_WBS_IFM( wb_agc_ , agc_submodule_ ),
                    .reset_i(reset_i), 
                    .aclk(aclk),
                    .dat_i(dat_i),
                    .dat_o(data_stage_connection));


    beamform_trigger #(.NBEAMS(NBEAMS)) 
        u_trigger(
            .clk_i(aclk),
            .data_i(data_stage_connection),

            .thresh_i(threshold_writing),
            .thresh_ce_i(trigger_threshold_ce_aclk),
            .update_i(trigger_threshold_update_aclk),        
            
            .trigger_o(trigger_o));



endmodule
