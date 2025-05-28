`timescale 1ns / 1ps
`include "interfaces.vh"

`define DLYFF #0.1

module L1_trigger_wrapper #(parameter NBEAMS=2, parameter AGC_TIMESCALE_REDUCTION_BITS = 2,
                    parameter WBCLKTYPE = "PSCLK", parameter CLKTYPE = "ACLK",
                    parameter TRIGGER_CLOCKS=375000000,// at 375 MHz this will count for 1 s  
                    parameter HOLDOFF_CLOCKS=16,
                    parameter STARTING_TARGET=100,
                    parameter STARTING_KP=1)( 

        input wb_clk_i,
        input wb_rst_i,

        `TARGET_NAMED_PORTS_WB_IF( wb_ , 22, 32 ), // Address width, data width.
        input reset_i, 
        input aclk,
        input [7:0][95:0] dat_i,
        
        output [NBEAMS-1:0] trigger_o
    );

    // function write_to_trigger (input [21:0] in_addr, input [31:0] in_data);
	// begin
    //     use_threshold_wb <= 1'b1;
    //     wr_threshold_wb <= 1'b1;
    //     address_threshold <= in_addr;
    //     data_threshold_o <= in_data;
	// end
    // endfunction

    task do_write_to_trigger; 
        input [21:0] in_addr;
        input [31:0] in_data;
        begin
            use_threshold_wb <= 1'b1;
            wr_threshold_wb <= 1'b1;
            address_threshold <= in_addr;
            data_threshold_o <= in_data;
        end
    endtask

    task finish_write_cycle_trigger; 
        begin
            use_threshold_wb <= 0'b1;
            wr_threshold_wb <= 0'b1;
            address_threshold <= 22'h0;
            data_threshold_o <= 32'h0;
        end
    endtask

    task do_read_req_trigger; 
        input [21:0] in_addr;
        begin
            use_threshold_wb <= 1'b1;
            wr_threshold_wb <= 0'b1;
            address_threshold <= in_addr;
        end
    endtask

    task finish_read_cycle_trigger; 
        output [31:0] out_data;
        begin
            use_threshold_wb <= 0'b1;
            wr_threshold_wb <= 0'b1;
            address_threshold <= 22'h0;
            out_data <= data_threshold_i;
        end
    endtask

    `define ADDR_MATCH( addr, val, mask ) ( ( addr & mask ) == (val & mask) )
    localparam [9:0] THRESHOLD_MASK = {10{1'b1}};
    localparam NBITS_KP = 32;
    localparam NFRAC_KP = 10;

    // Pass commands not about trigger rate control loop down
    `DEFINE_WB_IF( wb_L1_submodule_ , 22, 32);
    
    `DEFINE_WB_IF( wb_threshold_ , 22, 32);
    reg [21:0] address_threshold = {22{1'b0}};
    reg [31:0] data_threshold_o = {32{1'b0}};
    reg [31:0] data_threshold_i;
    reg use_threshold_wb = 0; // QOL tie these together if not ever implementing writing
    reg wr_threshold_wb = 0; // QOL tie these together if not ever implementing writing

    assign wb_threshold_dat_o = data_threshold_o;
    assign data_threshold_i = wb_threshold_dat_i;
    assign wb_threshold_adr_o = address_threshold;
    assign wb_threshold_cyc_o = use_threshold_wb;
    assign wb_threshold_stb_o = use_threshold_wb;
    assign wb_threshold_we_o = wr_threshold_wb; // Tie this in too if only ever writing
    assign wb_threshold_sel_o = {4{use_threshold_wb}};

    // //  Top interface target (S)        Connection interface (M)
    assign wb_ack_o = (wb_adr_i[14]) ? wb_L1_submodule_ack_i : (state == ACK);
    assign wb_err_o = (wb_adr_i[14]) ? wb_L1_submodule_err_i : 1'b0;
    assign wb_rty_o = (wb_adr_i[14]) ? wb_L1_submodule_rty_i : 1'b0;
    assign wb_dat_o = (wb_adr_i[14]) ? wb_L1_submodule_dat_i : response_reg;
    
    wire wb_control_loop_cyc_i;

    assign wb_L1_submodule_cyc_o = wb_cyc_i && !wb_adr_i[14];
    assign wb_control_loop_cyc_i = wb_cyc_i && wb_adr_i[14];
    assign wb_L1_submodule_stb_o = wb_stb_i;
    assign wb_L1_submodule_adr_o = wb_adr_i;
    assign wb_L1_submodule_dat_o = wb_dat_i;
    assign wb_L1_submodule_we_o = wb_we_i;
    assign wb_L1_submodule_sel_o = wb_sel_i;  

   
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] response_reg = 31'h0; // Pass back trigger count information

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] trigger_count_wb_reg; // Pass back # of triggers on WB

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] trigger_target_wb_reg = STARTING_TARGET; // The target number of triggers in the sample period

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] trigger_threshold_wb_reg; // Pass back threshold value on WB

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [NBITS_KP-1:0] trigger_control_K_P = STARTING_KP; // P Parameter for control loop. 
                                            // This is the fraction of error value to change threshold by.

    (* CUSTOM_CC_SRC = WBCLKTYPE *) // Store the thresholds here
    reg [NBEAMS-1:0][17:0] threshold_regs = {NBEAMS{18{1'b0}}};

    (* CUSTOM_CC_SRC = WBCLKTYPE *) // Store the last measured counts (rates) here
    reg [NBEAMS-1:0][31:0] trigger_count_reg = {NBEAMS{18{1'b0}}};

    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [17:0] threshold_writing = {18{1'b0}};

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] trigger_response = 32'h0; // L1 trigger replies


    // TODO Plan:   Use two state machines, one for this module's communication
    //              and one for managing the thresholds/rates. Both can be on the WB clock  
    //              since this is slow control.
    // Note: Completely unimplemented below this point
    // Note Note: Need to check whether this additional layer hurts timing. Don't expect so.


    // Upstream State machine control
    localparam FSM_BITS = 2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] WRITE = 1;
    localparam [FSM_BITS-1:0] READ = 2;
    localparam [FSM_BITS-1:0] ACK = 3;
    reg [FSM_BITS-1:0] state = IDLE;   

    //////////////////////////////////////////////////////////
    //////        Wishbone FSM For Upstream Comms       //////
    //////////////////////////////////////////////////////////
    always @(posedge wb_clk_i) begin
        
        // Determine what we are doing this cycle
        case (state)
            IDLE: if (wb_control_loop_cyc_i && wb_stb_i) begin
                if (wb_we_i) state <= WRITE;
                else state <= READ;
            end
            WRITE: state <= ACK;
            READ: state <= ACK;
            ACK: state <= IDLE;
            default: state <= IDLE; // Should never go here
        endcase
        
        // If reading, load the response in
        if (state == READ) begin
            // If bit [8] is 1, return the last-measured trigger count
            // Else if bit [9] is 1, return the current trigger threshold
            // Else return the loop parameter
            if(wb_adr_i[8]) response_reg <= trigger_count_reg[wb_adr_i[7:0]];
            else if(wb_adr_i[9]) response_reg <= {{(32-18){1'b0}}, threshold_regs[wb_adr_i[7:0]]};
            else response_reg <= {{(32-NBITS_KP){1'b0}}, trigger_control_K_P};
        end
        // If writing to a threshold, put it in the appropriate register
        if (state == WRITE) begin
            // NO CURRENT NEED FOR WRITING

            // if (wb_adr_i[8]) begin // The 8th bit is used to indicate a threshold write
            //     if (wb_sel_i[0]) threshold_regs[wb_adr_i[7:0]][7:0] <= wb_dat_i[7:0];
            //     if (wb_sel_i[1]) threshold_regs[wb_adr_i[7:0]][15:8] <= wb_dat_i[15:8];
            //     if (wb_sel_i[2]) threshold_regs[wb_adr_i[7:0]][17:16] <= wb_dat_i[17:16];
            // end             
        end
    end



    // Downstream State machine control
    localparam THRESHOLD_FSM_BITS = 3;
    localparam [THRESHOLD_FSM_BITS-1:0] THRESHOLD_POLLING = 0;
    localparam [THRESHOLD_FSM_BITS-1:0] THRESHOLD_WAITING = 1;
    localparam [THRESHOLD_FSM_BITS-1:0] THRESHOLD_READING = 2;
    localparam [THRESHOLD_FSM_BITS-1:0] THRESHOLD_CALCULATING = 3;
    localparam [THRESHOLD_FSM_BITS-1:0] THRESHOLD_UPDATING = 4;

    lcoalparam COMMFSM_BITS = 2;
    localparam [COMMFSM_BITS-1:0] COMM_SENDING = 0;
    localparam [COMMFSM_BITS-1:0] COMM_WAITING = 1;
    localparam [COMMFSM_BITS-1:0] COMM_CHECKING = 1;
    // localparam [COMMFSM_BITS-1:0] THRESHOLD_READING = 2;
    // localparam [COMMFSM_BITS-1:0] THRESHOLD_CALCULATING = 3;
    // localparam [COMMFSM_BITS-1:0] THRESHOLD_UPDATING = 4;

    reg [THRESHOLD_FSM_BITS-1:0] threshold_FSM_state = THRESHOLD_POLLING;  
    reg [THRESHOLD_FSM_BITS-1:0] comm_FSM_state = COMM_SENDING;  
    reg [$clog2(NBEAMS)+1:0] beam_idx = 0; // Control what beam we are looking at

    /////////////////////////////////////////////////////////////////
    //////       Control Loop FSM For Downstream Control       //////
    /////////////////////////////////////////////////////////////////
    always @(posedge wb_clk_i) begin
        
        // Determine what we are doing this cycle
        case (threshold_FSM_state)
            THRESHOLD_POLLING: begin // Start a trigger count cycle
                if(comm_FSM_state == COMM_SENDING) begin
                    do_write_to_trigger(22'h0, 32'h1);
                    comm_FSM_state <= COMM_WAITING;
                end else if(comm_FSM_state == COMM_WAITING) begin
                    if(wb_threshold_ack_i) begin // Command received, move on
                        finish_write_cycle_trigger();
                        comm_FSM_state <= COMM_SENDING;
                        threshold_FSM_state <= THRESHOLD_WAITING;
                    end
                end
            end
            THRESHOLD_WAITING: begin // Wait for count cycle to finish
                if(comm_FSM_state == COMM_SENDING) begin
                    do_read_req_trigger(22'h0);
                    comm_FSM_state <= COMM_WAITING;
                end else if(comm_FSM_state == COMM_WAITING) begin
                    if(wb_threshold_ack_i) begin // Command received, move on
                        finish_read_cycle_trigger(trigger_response);
                        comm_FSM_state <= COMM_CHECKING;
                    end
                end else if(comm_FSM_state == COMM_CHECKING) begin
                    if(trigger_response[0] == 1) begin // If the count cycle is done, move on
                        threshold_FSM_state <= THRESHOLD_READING;
                    end else begin // If the count cycle isn't done, ask again next clock
                        comm_FSM_state <= COMM_SENDING;
                    end
                end
            end
            // if(beam_idx < NBEAMS) begin // Poll this beam
            WRITE: threshold_FSM_state <= ACK;
            READ: threshold_FSM_state <= ACK;
            ACK: threshold_FSM_state <= IDLE;
            default: threshold_FSM_state <= THRESHOLD_POLLING; // Should never go here
        endcase
        
        // If reading, load the response in
        if (state == READ) begin
            // If bit [8] is 1, return the last-measured trigger count
            // Else if bit [9] is 1, return the current trigger threshold
            // Else return the loop parameter
            if(wb_adr_i[8]) response_reg <= trigger_count_reg[wb_adr_i[7:0]];
            else if(wb_adr_i[9]) response_reg <= {{(32-18){1'b0}}, threshold_regs[wb_adr_i[7:0]]};
            else response_reg <= {{(32-NBITS_KP){1'b0}}, trigger_control_K_P};
        end
        // If writing to a threshold, put it in the appropriate register
        if (state == WRITE) begin
            // NO CURRENT NEED FOR WRITING

            // if (wb_adr_i[8]) begin // The 8th bit is used to indicate a threshold write
            //     if (wb_sel_i[0]) threshold_regs[wb_adr_i[7:0]][7:0] <= wb_dat_i[7:0];
            //     if (wb_sel_i[1]) threshold_regs[wb_adr_i[7:0]][15:8] <= wb_dat_i[15:8];
            //     if (wb_sel_i[2]) threshold_regs[wb_adr_i[7:0]][17:16] <= wb_dat_i[17:16];
            // end             
        end
    end



    L1_trigger #(   .AGC_TIMESCALE_REDUCTION_BITS(AGC_TIMESCALE_REDUCTION_BITS), 
                    .TRIGGER_CLOCKS(TRIGGER_CLOCKS))
        u_L1_trigger(
            .wb_clk_i(wbclk_i),
            .wb_rst_i(wb_rst_i),
            `CONNECT_WBS_IFM( wb_ , wb_L1_submodule_ ),
            `CONNECT_WBS_IFM( wb_threshold_ , wb_threshold_ ),
            .reset_i(reset), 
            .aclk(aclk),
            .dat_i(sample_arr),
            .trigger_o(trigger));

endmodule
