`timescale 1ns / 1ps
`include "interfaces.vh"
`include "L1Beams_header_old.vh"

module L1_trigger_wrapper_tb;
    
    parameter       THIS_DESIGN = "NO_BQ";//"BASIC"
    parameter       HDL_FILTER_VERSION = "MINDSP";//"SYSTOLIC";
    parameter       THIS_STIM   = "FILE"; // Other options are:
                                                        //"GAUSS_STARTSTOP"
                                                        //"GAUSS_RESET"
                                                        //"ONLY_PULSES"
                                                        //"GAUSS_RAND_PULSES"
                                                        //"SINE"
                                                        //"GAUSS_RAND"
                                                        //"GAUSS_THRESH_WRITE"
                                                        //"ALL_SOFT_RESET"
                                                        //"AGC_READ"
                                                        //"ONLY_PULSES"
    // Clocks per L1 trigger sampling cycle
    parameter [47:0] TRIGGER_CLOCKS = 375; 
    parameter TIMESCALE_REDUCTION_BITS = 8; // Make the AGC period easier to simulate
    parameter NCHAN = 8;
    parameter NSAMP = 8;
    parameter NBITS = 12;
    parameter NBEAMS = 2;
    parameter ALIGNED_BEAM = 0;

    // Notch location
    localparam int notch [2] = {250, 400};
    localparam int Q [2] = {8,8};       
    localparam int GAUSS_NOISE_SIZE = 200;

    // Gaussian Random Parameters
    int seed = 1;
    int stim_mean = 5;
    int stim_sdev = 100; // Note that max value is 2047 (and -2048)

    // For use in generating test pulses
    int stim_val = 0;
    int cycling_num = 0;
    int cycling_offset = 0;
    int pulse_height = 400;

    // Definied delays, for use in *generating* pulses in this test stand
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

    reg use_L1 = 0; 
    reg wr_L1 = 0; 
    assign wb_L1_cyc_o = use_L1;
    assign wb_L1_stb_o = use_L1;
    assign wb_L1_we_o = wr_L1;
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
            do_write_L1(in_addr + 22'h4000 + 22'h2000, in_data);// Assert addr[14] and addr[13]
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


    // Trigger  output
    reg [NBEAMS-1:0]    trigger_reg; 
    wire [NBEAMS-1:0]   trigger;
    assign trigger_reg = trigger;

    // Reset
   reg reset_reg = 1'b0;
   wire reset;
   assign reset = reset_reg;

    // Reset
   reg wbreset_reg = 1'b0;
   wire wbreset;
   assign wbreset = wbreset_reg;
    
    generate
        if (THIS_DESIGN == "BASIC") begin : BASIC

            L1_trigger_wrapper #(   .AGC_TIMESCALE_REDUCTION_BITS(TIMESCALE_REDUCTION_BITS), 
                                    .TRIGGER_CLOCKS(TRIGGER_CLOCKS),
                                    .USE_BIQUADS("TRUE"),
                                    .HDL_FILTER_VERSION(HDL_FILTER_VERSION),
                                    .STARTING_TARGET(100), // Target triggers per period
                                    .COUNT_MARGIN(5), // +- Margin on triggers per period
                                    .STARTING_DELTA(100)) // Threshold change amount per correction
                u_L1_trigger(
                    .wb_clk_i(wbclk),
                    .wb_rst_i(wbreset),
                    `CONNECT_WBS_IFM( wb_ , wb_L1_ ),
                    .reset_i(reset), 
                    .aclk(aclk),
                    .dat_i(sample_arr),
                    .trigger_o(trigger));

        end else if(THIS_DESIGN == "NO_BQ") begin : NO_BIQUAD

            L1_trigger_wrapper #(   .AGC_TIMESCALE_REDUCTION_BITS(TIMESCALE_REDUCTION_BITS), 
                                    .TRIGGER_CLOCKS(TRIGGER_CLOCKS),
                                    .HDL_FILTER_VERSION(HDL_FILTER_VERSION),
                                    .USE_BIQUADS("FALSE"),
                                    .STARTING_TARGET(100), // Target triggers per period
                                    .COUNT_MARGIN(5), // +- Margin on triggers per period
                                    .STARTING_DELTA(100)) // Threshold change amount per correction
                u_L1_trigger(
                    .wb_clk_i(wbclk),
                    .wb_rst_i(wbreset),
                    `CONNECT_WBS_IFM( wb_ , wb_L1_ ),
                    .reset_i(reset), 
                    .aclk(aclk),
                    .dat_i(sample_arr),
                    .trigger_o(trigger));

        end
    endgenerate

    int fc; //, fd, f, fdebug; // File Descriptors for I/O of test
    int code, dummy, data_from_file; // Used for file I/O intermediate steps
    int coeff_from_file; // Intermediate transferring coefficient from file to biquad     
    reg [8*10:1] str; // String read from file

    int stim_val;
    reg [11:0] stim_vals [7:0] [7:0];
    reg [31:0] read_in_val = 32'd0;
    int f_outs [8] = {0,0,0,0,0,0,0,0};

    // Threshold, BQ initialization and AGC cycle
    initial begin : SETUP
        $display("Version 6.10.0");
        #200;
        // Let everything get settled
        @(posedge wbclk);
        @(posedge wbclk);

        if(THIS_DESIGN != "NO_BQ") begin: USING_BQ
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
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h04, coeff_from_file); // B
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h04, coeff_from_file); // A

                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h08, coeff_from_file); // C_2
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h08, coeff_from_file); // C_3  // Yes, this is the correct order according to the documentation
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h08, coeff_from_file); // C_1
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h08, coeff_from_file); // C_0

                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h0C, coeff_from_file); // a_1'  // For incremental computation
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h0C, coeff_from_file); // a_2'

                    // f FIR
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h10, coeff_from_file); // D_FF  
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h10, coeff_from_file); // X_6    
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h10, coeff_from_file); // X_5   
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h10, coeff_from_file);  // X_4   
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h10, coeff_from_file);  // X_3   
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h10, coeff_from_file);  // X_2   
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h10, coeff_from_file);  // X_1 
                
                    // g FIR
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h14, coeff_from_file);  // E_GG  
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h14, coeff_from_file); // X_7 
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h14, coeff_from_file);  // X_6
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h14, coeff_from_file);  // X_5    
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h14, coeff_from_file);  // X_4  
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h14, coeff_from_file);  // X_3  
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h14, coeff_from_file);  // X_2  
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h14, coeff_from_file);  // X_1 
                    
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h18, coeff_from_file);  // D_FG

                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h1C, coeff_from_file);  // E_GF

                    do_write_bq( bqidx*8'h80 + idx * 22'h400 + 8'h00, 32'd1 );     // Update
                end 
            end
        end

        #200;
        forever begin
            #0.01;
            for(int idx=0; idx<8; idx=idx+1) begin: AGC_LOOP_BY_CHAN
                do_read_agc(5'b10000 + idx * 22'h400, read_in_val);
                $display($sformatf("AGC 0x%1h: %1d",5'b10000 + idx * 22'h400, read_in_val));
                do_read_agc(5'b10000 + 1 + idx * 22'h400, read_in_val);
                $display($sformatf("AGC 0x%1h: %1d",5'b10000 + idx * 22'h400 + 1, read_in_val));
                do_read_agc(5'b00100 + idx * 22'h400, read_in_val);
                $display($sformatf("AGC 0x%1h: %1d",5'b10100 + idx * 22'h400, read_in_val));
                do_read_L1(0, read_in_val);
                $display($sformatf("trigger 0x%1h: %1d",0, read_in_val));
                do_read_L1(1, read_in_val);
                $display($sformatf("trigger 0x%1h: %1d",1, read_in_val));
                do_read_L1(2, read_in_val);
                $display($sformatf("trigger 0x%1h: %1d",2, read_in_val));
                do_read_L1(3, read_in_val);
                $display($sformatf("trigger 0x%1h: %1d",3, read_in_val));
                do_read_L1(4, read_in_val);
                $display($sformatf("trigger 0x%1h: %1d",4, read_in_val));
                do_read_L1(5, read_in_val);
                $display($sformatf("trigger 0x%1h: %1d",5, read_in_val));

            
            end
        end
    end


    // Stimulus
    int clocks = 0;
    int fd[7:0];
    int f;
    int code, dummy, data_from_file; // Used for file I/O intermediate steps
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
        end else if (THIS_STIM == "ONLY_PULSES") begin
            $display("THIS_DESIGN set to PULSES");  
            forever begin
                for(int i=0; i<TRIGGER_CLOCKS/2; i++) begin: FILL_DELAYED_PULSES
                    #0.01;
                    @(posedge aclk);
                    for(int j=0; j<NCHAN; j=j+1) begin : CHANNEL_FILL_DELAYED_PULSES
                        for(int k=0; k<NSAMP; k=k+1) begin : SAMPLE_FILL_DELAYED_PULSES
                            stim_val = 0;
                            cycling_num = i*8+k + delay_array[ALIGNED_BEAM][j];
                            cycling_offset = 8*50;
                            if((cycling_num-cycling_offset) < 12 && (cycling_num-cycling_offset) > 0) begin : ADD_PULSE
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
        end else if (THIS_STIM == "FILE") begin
            // Send in ADC data from files
            $display("Reading input from file");
            for(int in_count=0; in_count<600; in_count = in_count+1) begin
                for(int chan_idx=0; chan_idx<8; chan_idx = chan_idx+1) begin
                    fd[chan_idx] = $fopen($sformatf("freqs/inputs/thermal_surf_25_chan_%0d_event_%0d.csv", chan_idx, in_count),"r");
                end
                // f = $fopen($sformatf("freqs/outputs/thermal_surf_25_chan_%0d_event_%0d.txt", GAUSS_NOISE_SIZE, in_count, notch, Q), "w");

                // fdebug = $fopen($sformatf("freqs/outputs/trigger_chain_output_lpf_gauss_%1d_trial_%0d_notch_%0d_MHz_%1d.txt", GAUSS_NOISE_SIZE, in_count, notch, Q), "w");
                // $monitor($sformatf("freqs/outputs/trigger_chain_output_gauss_%1d_trial_%0d_notch_%0d_MHz_%1d.txt", GAUSS_NOISE_SIZE, in_count, notch,Q));

                code = 1;

                for(int clocks=0;clocks<((256)/8);clocks++) begin // 1024, but only take the first few
                    @(posedge aclk);
                    #0.01;
                    
                    for(int chan_idx=0; chan_idx<8; chan_idx = chan_idx+1) begin
                        for (int i=0; i<8; i++) begin
                            // Get the next inputs
                            code = $fgets(str, fd[chan_idx]);
                            dummy = $sscanf(str, "%d", data_from_file);
                            samples[chan_idx][i] = data_from_file;
                            // $fwrite(f,$sformatf("%1d\n",outsample[i]));
                            // $fwrite(fdebug,$sformatf("%1d\n",probe0[i]));
                            #0.01;
                        end
                    end
                end

                // Biquad reset
                reset_reg = 1'b1;
                for(int clocks=0;clocks<32;clocks++) begin
                    @(posedge aclk);
                    #0.01;
                end
                reset_reg = 1'b0;
                $fclose(fd);
                $fclose(fdebug);
                $fclose(f);
            end
        end else begin//if (THIS_STIM == "GAUSS_HARDRESET" ||THIS_STIM == "GAUSS_RESET" || THIS_STIM == "GAUSS_STARTSTOP" || THIS_STIM == "GAUSS_THRESH_WRITE" ) begin : GAUSS_RESET_RUN
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
        end
    end


    int reset_delay = TRIGGER_CLOCKS*3;
    int agc_reset_delay = TRIGGER_CLOCKS*5;
    initial begin
        if (THIS_STIM == "GAUSS_RESET") begin 
            forever begin:RESET_LOOP
                @(posedge aclk);
                reset_delay = reset_delay-1;
                if(reset_delay == 0) begin
                    do_write_L1(22'h1000, 0); 
                    reset_delay = TRIGGER_CLOCKS*3;
                end
            end
        end
    end

    initial begin
        if (THIS_STIM == "ALL_SOFT_RESET") begin 
            forever begin:SOFT_RESET_LOOP
                @(posedge aclk);
                reset_delay = reset_delay-1;
                if(reset_delay == 0) begin
                    do_write_L1(22'h1004, 1); 
                    reset_delay = TRIGGER_CLOCKS*6;
                end

                agc_reset_delay = agc_reset_delay-1;
                if(agc_reset_delay == 0) begin
                    do_write_L1(22'h1004, 2); 
                    agc_reset_delay = TRIGGER_CLOCKS*6;
                end
            end
        end
    end

    initial begin
        if (THIS_STIM == "GAUSS_HARDRESET") begin 
            forever begin:HARDRESET_LOOP
                @(posedge aclk);
                reset_delay = reset_delay-1;
                if(reset_delay == 0) begin
                    wbreset_reg = 0;
                    @(posedge wbclk)
                    wbreset_reg = 1;
                    @(posedge wbclk)
                    wbreset_reg = 0;
                    reset_delay = TRIGGER_CLOCKS*10;
                end
            end
        end
    end

    int stop_delay = TRIGGER_CLOCKS*3;
    int start_delay = TRIGGER_CLOCKS*1;
    initial begin
        if (THIS_STIM == "GAUSS_STARTSTOP") begin 
            forever begin: STARTSTOP_LOOP
                @(posedge aclk);
                if(start_delay>0) start_delay = start_delay-1;
                if(stop_delay>0) stop_delay = stop_delay-1;
                if(stop_delay == 0) begin
                    do_write_L1(22'h1000, 2); 
                     stop_delay = TRIGGER_CLOCKS*6;
                end     
                if(start_delay == 0) begin
                    do_write_L1(22'h1000, 1); 
                     start_delay = TRIGGER_CLOCKS*3;
                end

            end
        end
    end

    int stop_delay = TRIGGER_CLOCKS*3;
    int start_delay = TRIGGER_CLOCKS*1;
    int write_delay = TRIGGER_CLOCKS*5;
    initial begin
        if (THIS_STIM == "GAUSS_THRESH_WRITE") begin 
            forever begin: THRESH_WRITE_LOOP
                @(posedge aclk);
                if(start_delay>0) start_delay = start_delay-1;
                if(stop_delay>0) stop_delay = stop_delay-1;
                if(write_delay>0) write_delay = write_delay-1;
                if(stop_delay == 0) begin
                    do_write_L1(22'h1000, 2); 
                    stop_delay = TRIGGER_CLOCKS*6;
                end     
                if(start_delay == 0) begin
                    do_write_L1(22'h1000, 1); 
                    start_delay = TRIGGER_CLOCKS*6;
                end
                if(write_delay == 0) begin
                    do_write_L1(22'h0804, 500); 
                    write_delay = TRIGGER_CLOCKS*6;
                end

            end
        end
    end

    reg [21:0] AGC_out_data = 0;
    initial begin
        if (THIS_STIM == "AGC_READ") begin 
            forever begin: AGC_READ_LOOP
                @(posedge aclk);
                if(start_delay>0) start_delay = start_delay-1;
                if(start_delay == 0) begin
                    do_read_L1(22'h4000, AGC_out_data); 
                    do_read_L1(22'h4004, AGC_out_data);
                    do_read_L1(22'h4008, AGC_out_data);
                    do_read_L1(22'h400C, AGC_out_data);
                    do_read_L1(22'h4010, AGC_out_data);
                    do_read_L1(22'h4014, AGC_out_data);
                    do_read_L1(22'h4040, AGC_out_data);
                    do_read_L1(22'h4044, AGC_out_data);
                    start_delay = TRIGGER_CLOCKS*6;
                end
            end
        end
    end

    
endmodule
