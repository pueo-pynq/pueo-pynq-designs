`timescale 1ns / 1ps
`include "interfaces.vh"
`include "L1Beams_header.vh"
module L1_trigger_wrapper_tb;
    
    parameter       THIS_DESIGN = "BASIC";
    parameter       THIS_STIM   = "GAUSS_RAND";//_PULSES";//"SINE";//"GAUSS_RAND";
    parameter       TESTING_L1_CYCLE = "TRUE";
    parameter       TRIGGER_CLOCKS = 3750; // 10 Microseconds
    parameter TIMESCALE_REDUCTION_BITS = 8; // Make the AGC period easier to simulate
    parameter TARGET_RMS = 4;
    parameter NCHAN = 8;
    parameter NSAMP = 8;
    parameter NBITS = 12;
    parameter NBEAMS = 2;
    parameter ALIGNED_BEAM = 0;

    // PID control values. Note that this controller implementation cumulatively adds the output here
    // to the values. Other implementations therefore call this value "I". In a sense this is "P" for
    // the first derivative.
    parameter K_scale_P = -50.0;
    parameter K_offset_P = -1.0/8;

    // Notch location
    localparam int notch [2] = {250, 400};
    localparam int Q [2] = {8,8};       
    localparam int GAUSS_NOISE_SIZE = 200;

    // AGC Parameters
    int AGC_offset [8] = {0,0,0,0,0,0,0,0};

    localparam int INITIAL_SCALE = 1800;//2127;//found experimentally for sdvev = 100;
    int AGC_scale [8] = {INITIAL_SCALE, INITIAL_SCALE, INITIAL_SCALE, INITIAL_SCALE, INITIAL_SCALE, INITIAL_SCALE, INITIAL_SCALE, INITIAL_SCALE};//1024;
    // For a scale value of 32, 32/4096 = 1/128. With a pulse of 512 that becomes 4
    // This resulted in a value of 17 (16+1, so 1). I believe this is due to two fractional bits being removed? Maybe 3, with rounding.
    // Specifically, NFRAC_OUT in agc_dsp.sv

    // Gaussian Random Parameters
    int seed = 1;
    int stim_mean = 5;
    int stim_sdev = 100; // Note that max value is 2047 (and -2048)
    // int stim_clks = 500;//100007;

    int stim_val = 0;
    int cycling_num = 0;
    int cycling_offset = 0;
    int pulse_height = 0;//400;//0;

    // NOTE THE BIG-ENDIAN ARRAYS HERE
    localparam int delay_array [0:(`BEAM_TOTAL)-1][0:NCHAN-1] = `BEAM_ANTENNA_DELAYS;


    // Sine scale
    int sine_scale = 1;
    int sine_mag = 500;

    // Clocks
    wire wbclk;
    wire aclk;
    tb_rclk #(.PERIOD(10.0)) u_wbclk(.clk(wbclk));
    tb_rclk #(.PERIOD(5.0)) u_aclk(.clk(aclk));


    // WB interface for BQ and AGC in L1
    reg [21:0] address_L1 = {22{1'b0}};
    reg [31:0] data_L1_o = {32{1'b0}};
    reg [31:0] data_L1_i;// = {32{1'b0}};
    wire ack_L1;
    `DEFINE_WB_IF( wb_L1_ , 22, 32);
    assign wb_L1_dat_o = data_L1_o;
    assign data_L1_i = wb_L1_dat_i;
    assign wb_L1_adr_o = address_L1;
    assign ack_L1 = wb_L1_ack_i;

    reg use_L1 = 0; // QOL tie these together if not ever implementing writing
    reg wr_L1 = 0; // QOL tie these together if not ever implementing writing
    assign wb_L1_cyc_o = use_L1;
    assign wb_L1_stb_o = use_L1;
    assign wb_L1_we_o = wr_L1; // Tie this in too if only ever writing
    assign wb_L1_sel_o = {4{use_L1}};

    task do_write_L1; 
        input [21:0] in_addr;
        input [31:0] in_data;
        begin
            @(posedge wbclk);
            #1 use_L1 = 1; wr_L1=1; address_L1 = in_addr; data_L1_o = in_data;
            @(posedge wbclk);
            while (!ack_L1) #1 @(posedge wbclk);  
            #1 use_L1 = 0; wr_L1=0;
        end
    endtask

    task do_read_L1; 
        input [21:0] in_addr;
        output [31:0] out_data;
        begin 
            @(posedge wbclk);
            address_L1 = in_addr; #1
            #1 use_L1 = 1; wr_L1 = 0;
            @(posedge wbclk);
            while (!ack_L1) #1 @(posedge wbclk);  
            out_data = data_L1_i;
            #1 use_L1 = 0;
        end
    endtask

    task do_write_bq;
        input [21:0] in_addr;
        input [31:0] in_data;
        begin
            do_write_L1(in_addr + 22'h4000 + 22'h1000, in_data);// Assert addr[14] and addr[12]
        end
    endtask

    task do_write_agc;
        input [21:0] in_addr;
        input [31:0] in_data;
        begin
            do_write_L1(in_addr + 22'h4000, in_data);// Assert addr[14]
        end
    endtask

    task do_read_agc;
        input [21:0] in_addr;
        output [31:0] out_data;
        begin
            do_read_L1(in_addr + 22'h4000, out_data);// Assert addr[14]
        end
    endtask


    // ADC samples, both indexed and as one array
    reg [11:0] samples [7:0] [7:0];
    initial begin
        for (int idx=0;idx<8;idx=idx+1) begin: SAMPLE_INIT_CHAN_LOOP
            for (int j=0;j<8;j=j+1) samples[idx][j] <= 0;
        end
    end

    wire  [7:0][12*8-1:0] sample_arr;

    generate
        for (genvar idx=0;idx<8;idx=idx+1) begin: SAMPLE_ARR_CHAN_LOOP
            assign sample_arr[idx] =
                { samples[idx][7],
                samples[idx][6],
                samples[idx][5],
                samples[idx][4],
                samples[idx][3],
                samples[idx][2],
                samples[idx][1],
                samples[idx][0] };
        end
    endgenerate


    // Trigger and threshold control
    reg [17:0]          thresh_reg          = 18'd0;
    reg [NBEAMS-1:0]    thresh_ce_reg       = {NBEAMS{1'b0}};
    reg                 update_reg          = 1'b0;
    reg [NBEAMS-1:0]    trigger_reg; 

    wire [17:0]         thresh              = thresh_reg;
    wire [NBEAMS-1:0]   thresh_ce           = thresh_ce_reg;
    wire                update              = update_reg;
    wire [NBEAMS-1:0]   trigger;

    assign trigger_reg = trigger;


    // wire [5:0] outsample [7:0] [7:0]; // 8 channels and 8 samples.
    // wire [5*8-1:0] outsample_arr [7:0]; // 1 channel, samples appended

    // generate
    //     for (genvar idx=0;idx<8;idx=idx+1) begin: DEVEC_CHAN
    //         for (genvar k=0;k<8;k=k+1) begin : DEVEC
    //             assign outsample[idx][k] = outsample_arr[idx][5*k +: 5];
    //         end
    //     end
    // endgenerate

    // Reset
   reg reset_reg = 1'b0;
   wire reset;
   assign reset = reset_reg;
    
    generate
        if (THIS_DESIGN == "BASIC") begin : BASIC

            L1_trigger_wrapper #(   .AGC_TIMESCALE_REDUCTION_BITS(TIMESCALE_REDUCTION_BITS), 
                                    .TRIGGER_CLOCKS(TRIGGER_CLOCKS),
                                    .STARTING_TARGET(50), // Target triggers per period
                                    .COUNT_MARGIN(5), // +- Margin on triggers per period
                                    .STARTING_KP(100)) // Threshold change amount per correction
                u_L1_trigger(
                    .wb_clk_i(wbclk),
                    .wb_rst_i(1'b0),
                    `CONNECT_WBS_IFM( wb_ , wb_L1_ ),
                    .reset_i(reset), 
                    .aclk(aclk),
                    .dat_i(sample_arr),
                    .trigger_o(trigger));

        end else begin : DEFAULT

            // Something else

        end
    endgenerate


    reg [31:0] trigger_cycle_done = 32'd0;
    reg [31:0] trigger_threshold_value = 32'd0;
    reg [31:0] trigger_count_value = 32'd0;

    int fc; //, fd, f, fdebug; // File Descriptors for I/O of test
    int code, dummy, data_from_file; // Used for file I/O intermediate steps
    int coeff_from_file; // Intermediate transferring coefficient from file to biquad     
    reg [8*10:1] str; // String read from file

    int stim_val;
    reg [11:0] stim_vals [7:0] [7:0];
    reg [31:0] read_in_val = 32'd0;
    reg [24:0] agc_sq = 25'd0;
    real agc_sqrt = 0;
    real agc_scale_err = 0;
    int agc_scale_err_int = 0;
    int agc_gt = 0;
    int agc_lt = 0;
    int agc_offset_err = 0;
    int f_outs [8] = {0,0,0,0,0,0,0,0};


    // Threshold, BQ initialization and AGC cycle
    initial begin : SETUP
        $display("Version 6.10.0");
        #200;
        // Let everything get settled
        @(posedge wbclk);
        @(posedge wbclk);

        // @(posedge wbclk);
        // #1.75;
        // $display("Initial Threshold Load");
        // for(int beam_idx=0; beam_idx<NBEAMS; beam_idx++) begin
        //     // Note: 475 is 19000/40. Magic number hardcoded nonsense.
        //     do_write_trigger(22'h100 + beam_idx, 18'd19000 - beam_idx*(19000-2500)); // Load the trigger threshold
        //     do_write_trigger(22'h200 + beam_idx, 1); // Execute CE
        //     $display($sformatf("Prepping Beam %1d", beam_idx));
        // end
        // do_write_trigger(22'h0, 2); // Update all the thresholds

        // $display("Initial Threshold Has Been Loaded");

        for(int idx=0; idx<8; idx=idx+1) begin: BQ_PREP_BY_CHAN

            for (int bqidx=0; bqidx<2; bqidx = bqidx+1) begin: BQ_LOOP

                $display($sformatf("Prepping Chan %1d Biquad %1d", idx, bqidx));
                $display($sformatf("Notch at %1d MHz, Q at %1d", notch[bqidx], Q[bqidx]));
                $display("Using moving notch");
                // LOAD BIQUAD NOTCH COEFFICIENTS FROM A FILE
                if (bqidx==0) begin
                    fc = $fopen($sformatf("freqs/coefficients_updated/coeff_file_%1dMHz_%1d.dat", (notch[bqidx] + 15*idx), Q[bqidx]),"r");
                end else begin
                    fc = $fopen($sformatf("freqs/coefficients_updated/coeff_file_%1dMHz_%1d.dat", (notch[bqidx]), Q[bqidx]),"r");
                end

                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h04, coeff_from_file); // B
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h04, coeff_from_file); // A

                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h08, coeff_from_file); // C_2
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h08, coeff_from_file); // C_3  // Yes, this is the correct order according to the documentation
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h08, coeff_from_file); // C_1
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h08, coeff_from_file); // C_0

                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h0C, coeff_from_file); // a_1'  // For incremental computation
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h0C, coeff_from_file); // a_2'

                // f FIR
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h10, coeff_from_file); // D_FF  
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h10, coeff_from_file); // X_6    
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h10, coeff_from_file); // X_5   
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h10, coeff_from_file);  // X_4   
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h10, coeff_from_file);  // X_3   
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h10, coeff_from_file);  // X_2   
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h10, coeff_from_file);  // X_1 
            
                // g FIR
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h14, coeff_from_file);  // E_GG  
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h14, coeff_from_file); // X_7 
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h14, coeff_from_file);  // X_6
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h14, coeff_from_file);  // X_5    
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h14, coeff_from_file);  // X_4  
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h14, coeff_from_file);  // X_3  
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h14, coeff_from_file);  // X_2  
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h14, coeff_from_file);  // X_1 
                
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h18, coeff_from_file);  // D_FG

                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h1C, coeff_from_file);  // E_GF

                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h00, 32'd1 );     // Update
            end 
        end


        #200;

        // $display("Prepping AGCs");

        // for(int idx=0; idx<8; idx=idx+1) begin: AGC_PREP_BY_CHAN
            
        //     $display($sformatf("Prepping AGC %1d", idx));
        //     do_write_agc(22'h014 + idx * 22'h100, AGC_offset[idx]); // Set offset (from https://github.com/pueo-pynq/rfsoc-pydaq/blob/New/AGC/AGC_Daq.py)
        //     // I believe from other documentation
        //     // that scale is a fraction of 4096 (13 bits, 0x1000).
        //     do_write_agc(22'h010 + idx * 22'h100, AGC_scale[idx]); // Set scaling (from https://github.com/pueo-pynq/rfsoc-pydaq/blob/New/AGC/AGC_Daq.py)

        //     // My understanding is that these flag to the CE on the registers of the DSP where the new values are loaded in. 
        //     // The first signal here tells the offset and scale to load into the first FF
        //     // and the second signal applies them via the second FF.
        //     do_write_agc(22'h000 + idx * 22'h100, 12'h300); // AGC Load (from https://github.com/pueo-pynq/rfsoc-pydaq/blob/New/AGC/AGC_Daq.py)
        //     do_write_agc(22'h000 + idx * 22'h100, 12'h400); // AGC Apply (from https://github.com/pueo-pynq/rfsoc-pydaq/blob/New/AGC/AGC_Daq.py)

        //     #200;
        //     do_write_agc(22'h000 + idx * 22'h100, 12'h004); // Reset AGC
        //     do_write_agc(22'h000 + idx * 22'h100, 12'h001);//12'h001); // Start running AGC measurement cycle
            
        //     $display($sformatf("FINISHED AGC %1d", idx));
        // end        
        // do_write_trigger(22'h0, 1); // Begin a trigger count cycle
        // forever begin
        //     #0.01;
        //     // if(TESTING_L1_CYCLE == "TRUE") begin
        //     //     $display("Checking Trigger Cycle");    
        //     //     do_read_trigger(22'h0, trigger_cycle_done); // Begin a trigger count cycle
        //     //     if(trigger_cycle_done) begin
        //     //         $display($sformatf("Trigger Cycle Done: %1d",trigger_cycle_done));
        //     //         for(int beam_idx=0; beam_idx<NBEAMS; beam_idx=beam_idx+1) begin  
        //     //             do_read_trigger(22'h200 + beam_idx, trigger_threshold_value);   
        //     //             $display($sformatf("Trigger Threshold Value: %1d",trigger_threshold_value));    
        //     //             do_read_trigger(22'h100 + beam_idx, trigger_count_value);   
        //     //             $display($sformatf("Trigger Count Value: %1d",trigger_count_value));    
        //     //         end
        //     //         do_write_trigger(22'h0, 1); // Begin a trigger count cycle
        //     //         trigger_cycle_done = 32'd0; // Probably unnecessary
        //     //     end
        //     // end
        //     // for(int idx=0; idx<8; idx=idx+1) begin: AGC_LOOP_BY_CHAN

            //     // Check for complete AGC cycle
            //     do_read_agc(22'h000 + idx * 22'h100, read_in_val); // see if AGC is done
                
            //     $display($sformatf("CYCLING AGC %1d: read: %1d", idx, read_in_val));
            //     if(read_in_val) begin: agc_ready
            //         do_read_agc(22'h004 + idx * 22'h100, agc_sq); // the 3 address bits select the register to read. Lets get agc_scale at 
            //         do_read_agc(22'h008 + idx * 22'h100, agc_gt); // the 3 address bits select the register to read. Lets get agc_scale at 
            //         do_read_agc(22'h00c + idx * 22'h100, agc_lt); // the 3 address bits select the register to read. Lets get agc_scale at 
            //         agc_sq = {{(17-TIMESCALE_REDUCTION_BITS){1'd0}},{agc_sq[24:17-TIMESCALE_REDUCTION_BITS]}};// agc_sq/131072, equivalent to a shift of 17
            //         agc_sqrt = $sqrt(agc_sq);
            //         agc_scale_err = agc_sqrt - TARGET_RMS;
            //         agc_scale_err_int = agc_scale_err*7000000;
            //         agc_offset_err = agc_gt-agc_lt;
            //         AGC_scale[idx] = $floor(AGC_scale[idx] + agc_scale_err * K_scale_P);
            //         AGC_offset[idx] = $floor(AGC_offset[idx]+ agc_offset_err * K_offset_P);
            //         do_write_agc(22'h010 + idx * 22'h100, AGC_scale[idx]);
            //         do_write_agc(22'h014 + idx * 22'h100, AGC_offset[idx]);
            //         do_write_agc(22'h000 + idx * 22'h100, 12'h300); // AGC Load (from https://github.com/pueo-pynq/rfsoc-pydaq/blob/New/AGC/AGC_Daq.py)
            //         do_write_agc(22'h000 + idx * 22'h100, 12'h400); // AGC Apply (from https://github.com/pueo-pynq/rfsoc-pydaq/blob/New/AGC/AGC_Daq.py)


            //         do_write_agc(22'h000 + idx * 22'h100, 12'h004); // Reset AGC
            //         do_write_agc(22'h000 + idx * 22'h100, 12'h001); // Start running AGC measurement cycle
            //         read_in_val = 32'd0;
            //     end
            // end 
        // end
    end


    // Stimulus
    int clocks = 0;
    initial begin: STIM_LOOP
        #150;
        $display("Setup");
        for(int j=0; j<25; j=j+1) begin
            #1.75;
            @(posedge aclk);
        end
        #1.75;

        if (THIS_STIM == "GAUSS_RAND") begin : GAUSS_RAND_RUN

            $display("Beginning Random Gaussian Stimulus");
            
            forever begin: FILL_STIM_GAUSS_LOOP 
                #0.01;

                @(posedge aclk);
                for(int idx=0;idx<8;idx=idx+1) begin: FILL_STIM_GAUSS_CHAN_LOOP
                    for(int i=0; i<8; i++) begin: FILL_STIM_GAUSS
                        do begin
                            stim_val = $dist_normal(seed, stim_mean, stim_sdev);
                        end while(stim_val>2047 || stim_val < -2048);
                        stim_vals[idx][i] = stim_val;
                        // $fwrite(f_outs[idx],$sformatf("%1d\n",outsample[idx][i]));
                    end
                    samples[idx] = stim_vals[idx];
                end
            end
        end else if (THIS_STIM == "SINE") begin : SINE_RUN
    
            $display("Beginning CW Stimulus (UNTESTED)");

            forever begin: FILL_STIM_SINE_LOOP
                #0.01;
                @(posedge aclk);
                for(int idx=0;idx<8;idx=idx+1) begin: FILL_STIM_SINE_CHAN_LOOP
                    for(int i=0; i<8; i++) begin: FILL_STIM_SINE
                        for(int i=0; i<8; i++) begin: FILL_STIM_SINE
                            real inval = (clocks*8+i) / 100.0;
                            stim_vals[idx][i]  = $floor(sine_mag*$sin(sine_scale*inval));
                        end
                    end
                    samples[idx] = stim_vals[idx];
                end
            end
            $display("Ending CW Stimulus (how did this even happen?)");
            
        end else if (THIS_STIM == "GAUSS_RAND_PULSES") begin
            $display("THIS_DESIGN set to GAUSS_RAND_PULSES");  
            forever begin
                for(int i=0; i<64; i++) begin: FILL_DELAYED_PULSES
                    #0.01;
                    @(posedge aclk);
                    for(int j=0; j<NCHAN; j=j+1) begin : CHANNEL_FILL_DELAYED_PULSES
                        for(int k=0; k<NSAMP; k=k+1) begin : SAMPLE_FILL_DELAYED_PULSES
                            do begin
                                stim_val = $dist_normal(seed, stim_mean, stim_sdev);
                            end while(stim_val > 2047 || stim_val < -2048); // Don't leave 5 bit range please
                            cycling_num = i*8+k + delay_array[ALIGNED_BEAM][j];
                            cycling_offset = 8*50;
                            if((cycling_num-cycling_offset) < 12 && (cycling_num-cycling_offset) > 0) begin : ADD_PULSE
                                // if(j==0) begin
                                //     $display($sformatf("Number: %1d, rotating: %1d", (cycling_num-cycling_offset), (cycling_num-cycling_offset)%4));
                                // end
                                if((cycling_num-cycling_offset)%4 > 1) begin
                                    stim_val = stim_val + pulse_height/((cycling_num-cycling_offset)/3 + 1);
                                end else begin
                                    stim_val = stim_val - pulse_height/((cycling_num-cycling_offset)/3 + 1);
                                end
                                if(stim_val > 2047) begin
                                    stim_val = 2047;
                                end else if (stim_val < -2048) begin
                                    stim_val = -2048;
                                end
                            end
                            stim_vals[j][k] = stim_val;
                            // in_data_reg[j][k*12 +: 12] = stim_val;
                        end
                        samples[j] = stim_vals[j];// Not sure it has to be iterated like this
                    end
                end
            end   
        end
    end
    
endmodule
