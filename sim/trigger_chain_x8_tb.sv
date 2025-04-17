`timescale 1ns / 1ps
`include "interfaces.vh"
module trigger_chain_x8_tb;
    
    parameter       THIS_DESIGN = "BASIC";
    parameter       THIS_STIM   = "GAUSS_RAND";//"SINE";//"GAUSS_RAND";
    parameter TIMESCALE_REDUCTION_BITS = 5; // Make the AGC period easier to simulate
    parameter TARGET_RMS = 4;

    // PID control values. Note that this controller implementation cumulatively adds the output here
    // to the values. Other implementations therefore call this value "I". In a sense this is "P" for
    // the first derivative.
    parameter K_scale_P = -50.0;//-1.0/256;
    parameter K_offset_P = -1.0/8;//-1.0/256;

    // Biquad Parameters
    // int notch = 650;
    // int Q = 8; 

    // Notch location
    localparam int notch [2] = {250, 400};
    localparam int Q [2] = {8,8};       
    localparam int GAUSS_NOISE_SIZE = 200;

    // AGC Parameters
    int AGC_offset [8] = {0,0,0,0,0,0,0,0};

    localparam int INITIAL_SCALE = 2512;//4096;
    int AGC_scale [8] = {INITIAL_SCALE, INITIAL_SCALE, INITIAL_SCALE, INITIAL_SCALE, INITIAL_SCALE, INITIAL_SCALE, INITIAL_SCALE, INITIAL_SCALE};//1024;
    // For a scale value of 32, 32/4096 = 1/128. With a pulse of 512 that becomes 4
    // This resulted in a value of 17 (16+1, so 1). I believe this is due to two fractional bits being removed? Maybe 3, with rounding.
    // Specifically, NFRAC_OUT in agc_dsp.sv

    // Gaussian Random Parameters
    int seed = 1;
    int stim_mean = 0;
    int stim_sdev = 100; // Note that max value is 2047 (and -2048)
    // int stim_clks = 500;//100007;

    // Sine scale
    int sine_scale = 1;
    int sine_mag = 500;

    // Clocks
    wire wbclk;
    wire aclk;
    tb_rclk #(.PERIOD(10.0)) u_wbclk(.clk(wbclk));
    tb_rclk #(.PERIOD(5.0)) u_aclk(.clk(aclk));

    // Wishbone Communication 
    // For Biquad
    reg wr = 0;
    reg [21:0] address = {22{1'b0}};
    reg [31:0] data = {32{1'b0}};
    wire ack;
    `DEFINE_WB_IF( wb_ , 22, 32);
    assign wb_cyc_o = wr;
    assign wb_stb_o = wr;
    assign wb_we_o = wr;
    assign wb_sel_o = {4{wr}};
    assign wb_dat_o = data;
    assign wb_adr_o = address;
    assign ack = wb_ack_i;

    task do_write_bq; 
        input [21:0] in_addr;
        input [31:0] in_data;
        begin
            @(posedge wbclk);
            #1 wr = 1; address = in_addr; data = in_data;
            @(posedge wbclk);
            while (!ack) #1 @(posedge wbclk); 
            #1 wr = 0;
        end
    endtask

    // For AGC (One channel at first)
    reg [21:0] address_agc = {22{1'b0}};
    reg [31:0] data_agc_o = {32{1'b0}};
    reg [31:0] data_agc_i;// = {32{1'b0}};
    wire ack_agc;
    `DEFINE_WB_IF( wb_agc_ , 22, 32);
    assign wb_agc_dat_o = data_agc_o;
    assign data_agc_i = wb_agc_dat_i;
    assign wb_agc_adr_o = address_agc;
    assign ack_agc = wb_agc_ack_i;

    // reg wr_agc = 0; // QOL tie these together if not ever implementing writing
    // assign wb_agc_cyc_o = wr_agc;
    // assign wb_agc_stb_o = wr_agc;
    // assign wb_agc_we_o = wr_agc;
    // assign wb_agc_sel_o = {4{wr_agc}};

    reg use_agc = 0; // QOL tie these together if not ever implementing writing
    reg wr_agc = 0; // QOL tie these together if not ever implementing writing
    assign wb_agc_cyc_o = use_agc;
    assign wb_agc_stb_o = use_agc;
    assign wb_agc_we_o = wr_agc; // Tie this in too if only ever writing
    assign wb_agc_sel_o = {4{use_agc}};

    task do_write_agc; 
        input [21:0] in_addr;
        input [31:0] in_data;
        begin
            @(posedge wbclk);
            #1 use_agc = 1; wr_agc=1; address_agc = in_addr; data_agc_o = in_data;
            @(posedge wbclk);
            while (!ack_agc) #1 @(posedge wbclk);  
            #1 use_agc = 0; wr_agc=0;
        end
    endtask

    task do_read_agc; 
        input [7:0] in_addr;
        output [31:0] out_data;
        begin 
            address_agc = in_addr; #1
            #1 use_agc = 1; wr_agc = 0;
            @(posedge wbclk);
            while (!ack_agc) #1 @(posedge wbclk);  
            out_data = data_agc_i;
            #1 use_agc = 0;
        end
    endtask

    // // Probes
    // // Output Samples, both indexed and as one array
    // wire [11:0] probe0[7:0];
    // wire [12*8-1:0] probe0_arr;
    // generate
    //     genvar j;
    //     for (j=0;j<8;j=j+1) begin : DEVEC_PROBE0
    //         assign probe0[j] = probe0_arr[12*j +: 12];
    //     end
    // endgenerate

    // ADC samples, both indexed and as one array
    reg [11:0] samples [7:0] [7:0];
    initial begin
        for (int idx=0;idx<8;idx=idx+1) begin: SAMPLE_INIT_CHAN_LOOP
            for (int j=0;j<8;j=j+1) samples[idx][j] <= 0;
        end
    end


    wire [12*8-1:0] sample_arr [7:0];

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


    wire [5:0] outsample [7:0] [7:0]; // 8 channels and 8 samples.
    wire [5*8-1:0] outsample_arr [7:0]; // 1 channel, samples appended

    generate
        for (genvar idx=0;idx<8;idx=idx+1) begin: DEVEC_CHAN
            for (genvar k=0;k<8;k=k+1) begin : DEVEC
                assign outsample[idx][k] = outsample_arr[idx][5*k +: 5];
            end
        end
    endgenerate

    // Reset
   reg reset_reg = 1'b0;
   wire reset;
   assign reset = reset_reg;
    
    generate
        if (THIS_DESIGN == "BASIC") begin : BASIC

            trigger_chain_x8_wrapper #(.AGC_TIMESCALE_REDUCTION_BITS(TIMESCALE_REDUCTION_BITS))
                u_chain(
                    .wb_clk_i(wbclk),
                    .wb_rst_i(1'b0),
                    `CONNECT_WBS_IFM( wb_bq_ , wb_ ),
                    `CONNECT_WBS_IFM( wb_agc_ , wb_agc_ ),
                    .reset_i(reset), 
                    .aclk(aclk),
                    .dat_i(sample_arr),
                    .dat_o(outsample_arr));

        end else begin : DEFAULT // Currently the same as "BASIC"
            // trigger_chain_design u_chain(
            //     .wb_clk_i(wbclk),
            //     .wb_rst_i(1'b0),
            //     `CONNECT_WBS_IFM( wb_ , wb_ ),
            //     `CONNECT_WBS_IFM( wb_agc_ , wb_agc_ ),
            //     .reset_i(reset), 
            //     .aclk(aclk),
            //     .dat_i(sample_arr),
            //     .dat_o(outsample_arr));
        end
    endgenerate

    int fc, fd, f, fdebug; // File Descriptors for I/O of test
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


    // BQ initialization and AGC cycle
    initial begin : SETUP

        #200;
        // Let everything get settled
        @(posedge wbclk);
        @(posedge wbclk);

        for(int idx=0; idx<8; idx=idx+1) begin: BQ_PREP_BY_CHAN

            for (int bqidx=0; bqidx<2; bqidx = bqidx+1) begin: BQ_LOOP

                $monitor($sformatf("Prepping Biquad %1d", bqidx));
                $monitor($sformatf("Notch at %1d MHz, Q at %1d", notch[bqidx], Q[bqidx]));
                $monitor("Using moving notch");
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
                do_write_bq( bqidx*8'h80 + idx * 22'h100 + 8'h0C, coeff_from_file); // a_1'  // For incremental computation, unused
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

        $monitor("Prepping AGCs");

        for(int idx=0; idx<8; idx=idx+1) begin: AGC_PREP_BY_CHAN
            
            $monitor($sformatf("Prepping AGC %1d", idx));
            do_write_agc(22'h014 + idx * 22'h100, AGC_offset[idx]); // Set offset (from https://github.com/pueo-pynq/rfsoc-pydaq/blob/New/AGC/AGC_Daq.py)
            // I believe from other documentation
            // that scale is a fraction of 4096 (13 bits, 0x1000).
            do_write_agc(22'h010 + idx * 22'h100, AGC_scale[idx]); // Set scaling (from https://github.com/pueo-pynq/rfsoc-pydaq/blob/New/AGC/AGC_Daq.py)

            // My understanding is that these flag to the CE on the registers of the DSP where the new values are loaded in. 
            // The first signal here tells the offset and scale to load into the first FF
            // and the second signal applies them via the second FF.
            do_write_agc(22'h000 + idx * 22'h100, 12'h300); // AGC Load (from https://github.com/pueo-pynq/rfsoc-pydaq/blob/New/AGC/AGC_Daq.py)
            do_write_agc(22'h000 + idx * 22'h100, 12'h400); // AGC Apply (from https://github.com/pueo-pynq/rfsoc-pydaq/blob/New/AGC/AGC_Daq.py)

            #200;
            do_write_agc(22'h000 + idx * 22'h100, 12'h004); // Reset AGC
            do_write_agc(22'h000 + idx * 22'h100, 12'h001); // Start running AGC measurement cycle
            
            $monitor($sformatf("FINISHED AGC %1d", idx));
        end
        forever begin
            #0.01;
            for(int idx=0; idx<8; idx=idx+1) begin: AGC_LOOP_BY_CHAN
                // Check for complete AGC cycle
                do_read_agc(22'h000 + idx * 22'h100, read_in_val); // see if AGC is done
                if(read_in_val) begin: agc_ready
                    do_read_agc(22'h004 + idx * 22'h100, agc_sq); // the 3 address bits select the register to read. Lets get agc_scale at 
                    do_read_agc(22'h008 + idx * 22'h100, agc_gt); // the 3 address bits select the register to read. Lets get agc_scale at 
                    do_read_agc(22'h00c + idx * 22'h100, agc_lt); // the 3 address bits select the register to read. Lets get agc_scale at 
                    agc_sq = {{(17-TIMESCALE_REDUCTION_BITS){1'd0}},{agc_sq[24:17-TIMESCALE_REDUCTION_BITS]}};// agc_sq/131072, equvalent to a shift of 17
                    agc_sqrt = $sqrt(agc_sq);
                    agc_scale_err = agc_sqrt - TARGET_RMS;
                    agc_scale_err_int = agc_scale_err*7000000;
                    agc_offset_err = agc_gt-agc_lt;
                    AGC_scale[idx] = $floor(AGC_scale[idx] + agc_scale_err * K_scale_P);
                    AGC_offset[idx] = $floor(AGC_offset[idx]+ agc_offset_err * K_offset_P);
                    do_write_agc(22'h010 + idx * 22'h100, AGC_scale[idx]);
                    do_write_agc(22'h014 + idx * 22'h100, AGC_offset[idx]);
                    do_write_agc(22'h000 + idx * 22'h100, 12'h300); // AGC Load (from https://github.com/pueo-pynq/rfsoc-pydaq/blob/New/AGC/AGC_Daq.py)
                    do_write_agc(22'h000 + idx * 22'h100, 12'h400); // AGC Apply (from https://github.com/pueo-pynq/rfsoc-pydaq/blob/New/AGC/AGC_Daq.py)


                    do_write_agc(22'h000 + idx * 22'h100, 12'h004); // Reset AGC
                    do_write_agc(22'h000 + idx * 22'h100, 12'h001); // Start running AGC measurement cycle
                    read_in_val = 32'd0;
                end
            end 
        end

    end


    // Stimulus with Biquad Notch Loop  
    int clocks = 0;
    initial begin: STIM_LOOP
        #150;

        if (THIS_STIM == "FILE_DEP") begin : FILE_RUN
                // Notch location
            // for(int notch=260; notch<1200; notch = notch+5000) begin

            //     // Qs for notch
            //     for(int Q=7; Q<8; Q = Q+50) begin


            //         for (int bqidx=0; bqidx<2; bqidx = bqidx+1) begin: BQ_LOOP

            //             $monitor($sformatf("Prepping Biquad %1d", bqidx));
            //             $monitor($sformatf("Notch at %1d MHz, Q at %1d", notch+bqidx*200, Q));

            //             // LOAD BIQUAD NOTCH COEFFICIENTS FROM A FILE
            //             fc = $fopen($sformatf("freqs/coefficients_updated/coeff_file_%1dMHz_%1d.dat", notch+bqidx*200, Q),"r");

            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h04, coeff_from_file); // B
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h04, coeff_from_file); // A

            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h08, coeff_from_file); // C_2
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h08, coeff_from_file); // C_3  // Yes, this is the correct order according to the documentation
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h08, coeff_from_file); // C_1
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h08, coeff_from_file); // C_0

            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h0C, coeff_from_file); // a_1'  // For incremental computation, unused
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h0C, coeff_from_file); // a_2'

            //             // f FIR
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h10, coeff_from_file); // D_FF  
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h10, coeff_from_file); // X_6    
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h10, coeff_from_file); // X_5   
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h10, coeff_from_file);  // X_4   
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h10, coeff_from_file);  // X_3   
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h10, coeff_from_file);  // X_2   
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h10, coeff_from_file);  // X_1 
                    
            //             // g FIR
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h14, coeff_from_file);  // E_GG  
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h14, coeff_from_file); // X_7 
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h14, coeff_from_file);  // X_6
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h14, coeff_from_file);  // X_5    
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h14, coeff_from_file);  // X_4  
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h14, coeff_from_file);  // X_3  
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h14, coeff_from_file);  // X_2  
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h14, coeff_from_file);  // X_1 
                        
            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h18, coeff_from_file);  // D_FG

            //             code = $fgets(str, fc);
            //             dummy = $sscanf(str, "%d", coeff_from_file);
            //             do_write_bq( bqidx*8'h80 + 8'h1C, coeff_from_file);  // E_GF

            //             do_write_bq( bqidx*8'h80 + 8'h00, 32'd1 );     // Update
            //         end 
                    
            //         $monitor("Prepping AGC");
                    
            //         do_write_agc(8'h14, AGC_offset); // Set offset (from https://github.com/pueo-pynq/rfsoc-pydaq/blob/New/AGC/AGC_Daq.py)
            //         // I believe from other documentation
            //         // that scale is a fraction of 4096 (13 bits, 0x1000).
            //         do_write_agc(8'h10, AGC_scale); // Set scaling (from https://github.com/pueo-pynq/rfsoc-pydaq/blob/New/AGC/AGC_Daq.py)


            //         // My understanding is that these flag to the CE on the registers of the DSP where the new values are loaded in. 
            //         // The first signal here tells the offset and scale to load into the first FF
            //         // and the second signal applies them via the second FF.
            //         do_write_agc(8'h00, 12'h300); // AGC Load (from https://github.com/pueo-pynq/rfsoc-pydaq/blob/New/AGC/AGC_Daq.py)
            //         do_write_agc(8'h00, 12'h400); // AGC Apply (from https://github.com/pueo-pynq/rfsoc-pydaq/blob/New/AGC/AGC_Daq.py)


            //         // SEND IN AN IMPULSE
            //         #500;
            //         fd = $fopen($sformatf("freqs/inputs/pulse_input_height_512_clipped.dat"),"r");
            //         f = $fopen($sformatf("freqs/outputs/trigger_chain_pulse_output_height_512_notch_%1dMHz_%1dQ.dat", notch, Q), "w");
            //         // fdebug = $fopen($sformatf("freqs/outputs/trigger_chain_pulse_output_debug_height_512_notch_%1dMHz_%1dQ_expanded.dat", notch, Q), "w");


            //         for(int clocks=0;clocks<10007;clocks++) begin // We are expecting 80064 samples, cut the end
            //             @(posedge aclk);
            //             #0.01;
            //             for (int i=0; i<8; i++) begin
            //                 // Get the next inputs
            //                 code = $fgets(str, fd);
            //                 dummy = $sscanf(str, "%d", data_from_file);
            //                 samples[i] = data_from_file;
            //                 // $monitor("Hello World in loop");
            //                 // $monitor($sformatf("sample is %1d", data_from_file));
            //                 $fwrite(f,$sformatf("%1d\n",outsample[i]));
            //                 #0.01;
            //             end
            //             // $fwrite(fdebug,$sformatf("%1d\n",0));
            //             // $fwrite(fdebug,$sformatf("%1d\n",0));
            //             // $fwrite(fdebug,$sformatf("%1d\n",0));
            //             // $fwrite(fdebug,$sformatf("%1d\n",0));
            //             // $fwrite(fdebug,$sformatf("%1d\n",0));
            //             // $fwrite(fdebug,$sformatf("%1d\n",0));
            //             // $fwrite(fdebug,$sformatf("%1d\n",0));
            //             // $fwrite(fdebug,$sformatf("%1d\n",0));
            //         end

            //         // Biquad reset
            //         reset_reg = 1'b1;
            //         for(int clocks=0;clocks<32;clocks++) begin
            //             @(posedge aclk);
            //             #0.01;
            //         end
            //         reset_reg = 1'b0;

            //         $fclose(fd);
            //         // $fclose(fdebug);
            //         $fclose(f);

            //         // SEND IN THE GAUSSIAN HANNING WINDOWS

            //         for(int in_count=0; in_count<10; in_count = in_count+1) begin
                        
            //             fd = $fopen($sformatf("freqs/inputs/gauss_input_%1d_sigma_hanning_clipped_%0d.dat", GAUSS_NOISE_SIZE, in_count),"r");
            //             f = $fopen($sformatf("freqs/outputs/trigger_chain_output_gauss_%1d_trial_%0d_notch_%0d_MHz_%1d.txt", GAUSS_NOISE_SIZE, in_count, notch, Q), "w");
            //             // fdebug = $fopen($sformatf("freqs/outputs/trigger_chain_output_lpf_gauss_%1d_trial_%0d_notch_%0d_MHz_%1d.txt", GAUSS_NOISE_SIZE, in_count, notch, Q), "w");
            //             $monitor($sformatf("freqs/outputs/trigger_chain_output_gauss_%1d_trial_%0d_notch_%0d_MHz_%1d.txt", GAUSS_NOISE_SIZE, in_count, notch,Q));

            //             code = 1;

            //             for(int clocks=0;clocks<10007;clocks++) begin // We are expecting 80064 samples, cut the end
            //                 @(posedge aclk);
            //                 #0.01;
            //                 for (int i=0; i<8; i++) begin
            //                     // Get the next inputs
            //                     code = $fgets(str, fd);
            //                     dummy = $sscanf(str, "%d", data_from_file);
            //                     samples[i] = data_from_file;
            //                     $fwrite(f,$sformatf("%1d\n",outsample[i]));
            //                     // $fwrite(fdebug,$sformatf("%1d\n",probe0[i]));
            //                     #0.01;
            //                 end
            //             end

            //             // Biquad reset
            //             reset_reg = 1'b1;
            //             for(int clocks=0;clocks<32;clocks++) begin
            //                 @(posedge aclk);
            //                 #0.01;
            //             end
            //             reset_reg = 1'b0;
            //             $fclose(fd);
            //             // $fclose(fdebug);
            //             $fclose(f);
            //         end
            //     end
            // end
        end else if (THIS_STIM == "GAUSS_RAND") begin : GAUSS_RAND_RUN


            $monitor("Beginning Random Gaussian Stimulus");
            for(int idx=0;idx<8;idx=idx+1) begin: OPEN_FILE_LOOP
                f_outs[idx] = $fopen($sformatf("freqs/outputs/trigger_chain_output_%1d_gauss_moving_notch_trial.txt", idx), "w");
            end
            forever begin: FILL_STIM_GAUSS_LOOP // We are expecting 80064 samples, cut the end
                #0.01;

                @(posedge aclk);
                for(int idx=0;idx<8;idx=idx+1) begin: FILL_STIM_GAUSS_CHAN_LOOP
                    for(int i=0; i<8; i++) begin: FILL_STIM_GAUSS
                        do begin
                            stim_val = $dist_normal(seed, stim_mean, stim_sdev);
                        end while(stim_val>2047 || stim_val < -2048);
                        stim_vals[idx][i] = stim_val;
                        $fwrite(f_outs[idx],$sformatf("%1d\n",outsample[idx][i]));
                    end
                    samples[idx] = stim_vals[idx];
                end
            end
        end else if (THIS_STIM == "SINE") begin : SINE_RUN
    
            $monitor("Beginning CW Stimulus (UNTESTED)");

            forever begin: FILL_STIM_SINE_LOOP // We are expecting 80064 samples, cut the end
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
            $monitor("Ending CW Stimulus (how did this even happen?)");
            
        end else begin
            $monitor("THIS_DESIGN set to something other");     
        end
    end
    
endmodule
