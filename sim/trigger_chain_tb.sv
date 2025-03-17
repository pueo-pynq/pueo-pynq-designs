`timescale 1ns / 1ps
module trigger_chain_tb;
    
    parameter       THIS_DESIGN = "BASIC";

    // Biquad Parameters
    int notch = 650;
    int Q = 8;        
    localparam int GAUSS_NOISE_SIZE = 1000;


    // Clocks
    wire wbclk;
    wire aclk;
    tb_rclk #(.PERIOD(10.0)) u_wbclk(.clk(wbclk));
    tb_rclk #(.PERIOD(5.0)) u_aclk(.clk(aclk));

    // Wishbone Communication
    reg wr = 0;
    reg [7:0] address = {8{1'b0}};
    reg [31:0] data = {32{1'b0}};
    wire ack;
    `DEFINE_WB_IF( wb_ , 8, 32);
    assign wb_cyc_o = wr;
    assign wb_stb_o = wr;
    assign wb_we_o = wr;
    assign wb_sel_o = {4{wr}};
    assign wb_dat_o = data;
    assign wb_adr_o = address;
    assign ack = wb_ack_i;

    task do_write; //  TODO The issue could be the lack of a flag sync in biquad8_double_design.sv, unlike biquad8_wrapper.sv //L
        input [7:0] in_addr;
        input [31:0] in_data;
        begin
            @(posedge wbclk);
            #1 wr = 1; address = in_addr; data = in_data;
            @(posedge wbclk);
            while (!ack) #1 @(posedge wbclk); // TODO This is getting passed by not-ing high impedence 
            #1 wr = 0;
        end
    endtask

    // Probes
    // Output Samples, both indexed and as one array
    wire [11:0] probe0[7:0];
    wire [12*8-1:0] probe0_arr;
    generate
        genvar j;
        for (j=0;j<8;j=j+1) begin : DEVEC_PROBE0
            assign probe0[j] = probe0_arr[12*j +: 12];
        end
    endgenerate

    // ADC samples, both indexed and as one array
    reg [11:0] samples[7:0];
    initial for (int i=0;i<8;i=i+1) samples[i] <= 0;
    wire [12*8-1:0] sample_arr =
        { samples[7],
          samples[6],
          samples[5],
          samples[4],
          samples[3],
          samples[2],
          samples[1],
          samples[0] };

    // Output Samples, both indexed and as one array
    wire [11:0] outsample[7:0];
    wire [12*8-1:0] outsample_arr;
    generate
        genvar k;
        for (k=0;k<8;k=k+1) begin : DEVEC
            assign outsample[k] = outsample_arr[12*k +: 12];
        end
    endgenerate

    // Biquad reset
   reg bq_reset_reg = 1'b0;
   wire bq_reset;
   assign bq_reset = bq_reset_reg;
    
    if (THIS_DESIGN == "BASIC") begin : BASIC

        trigger_chain_design u_chain(
            .wb_clk_i(wbclk),
            .wb_rst_i(1'b0),
            `CONNECT_WBS_IFM( wb_ , wb_ ),
            .reset_BQ_i(bq_reset), 
            .aclk(aclk),
            .dat_i(sample_arr),
            .dat_o(outsample_arr),
            .probes(probe0_arr));

    end else begin : DEFAULT // Currently the same as "BASIC"
        trigger_chain_design u_chain(
            .wb_clk_i(wbclk),
            .wb_rst_i(1'b0),
            `CONNECT_WBS_IFM( wb_ , wb_ ),
            .reset_BQ_i(bq_reset), 
            .aclk(aclk),
            .dat_i(sample_arr),
            .dat_o(outsample_arr),
            .probes(probe0_arr));
    end

    integer fc, fd, f, fdebug; // File Descriptors for I/O of test
    integer code, dummy, data_from_file; // Used for file I/O intermediate steps
    integer coeff_from_file; // Intermediate transferring coefficient from file to biquad     
    reg [8*10:1] str; // String read from file

    initial begin
        #150;


        if (THIS_DESIGN == "BASIC") begin : BASIC_RUN
                // Notch location
            for(int notch=600; notch<1200; notch = notch+5000) begin

                // Qs for notch
                for(int Q=3; Q<8; Q = Q+50) begin


                    for (int bqidx=0; bqidx<2; bqidx = bqidx+1) begin: BQ_LOOP

                        $monitor($sformatf("Prepping Biquad %1d", bqidx));
                        $monitor($sformatf("Notch at %1d MHz, Q at %1d", notch+bqidx*150, Q));

                        // LOAD BIQUAD NOTCH COEFFICIENTS FROM A FILE
                        fc = $fopen($sformatf("freqs/coefficients_updated/coeff_file_%1dMHz_%1d.dat", notch+bqidx*150, Q),"r");

                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h04, coeff_from_file); // B
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h04, coeff_from_file); // A

                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h08, coeff_from_file); // C_2
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h08, coeff_from_file); // C_3  // Yes, this is the correct order according to the documentation
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h08, coeff_from_file); // C_1
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h08, coeff_from_file); // C_0

                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h0C, coeff_from_file); // a_1'  // For incremental computation, unused
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h0C, coeff_from_file); // a_2'

                        // f FIR
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h10, coeff_from_file); // D_FF  
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h10, coeff_from_file); // X_6    
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h10, coeff_from_file); // X_5   
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h10, coeff_from_file);  // X_4   
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h10, coeff_from_file);  // X_3   
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h10, coeff_from_file);  // X_2   
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h10, coeff_from_file);  // X_1 
                    
                        // g FIR
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h14, coeff_from_file);  // E_GG  
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h14, coeff_from_file); // X_7 
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h14, coeff_from_file);  // X_6
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h14, coeff_from_file);  // X_5    
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h14, coeff_from_file);  // X_4  
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h14, coeff_from_file);  // X_3  
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h14, coeff_from_file);  // X_2  
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h14, coeff_from_file);  // X_1 
                        
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h18, coeff_from_file);  // D_FG

                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( bqidx*8'h80 + 8'h1C, coeff_from_file);  // E_GF

                        do_write( bqidx*8'h80 + 8'h00, 32'd1 );     // Update
                    end 

                    // SEND IN AN IMPULSE
                    #500;
                    fd = $fopen($sformatf("freqs/inputs/pulse_input_height_512_clipped.dat"),"r");
                    f = $fopen($sformatf("freqs/outputs/trigger_chain_pulse_output_height_512_notch_%1dMHz_%1dQ.dat", notch, Q), "w");
                    fdebug = $fopen($sformatf("freqs/outputs/trigger_chain_pulse_output_debug_height_512_notch_%1dMHz_%1dQ_expanded.dat", notch, Q), "w");


                    for(int clocks=0;clocks<10007;clocks++) begin // We are expecting 80064 samples, cut the end
                        @(posedge aclk);
                        #0.01;
                        for (int i=0; i<8; i++) begin
                            // Get the next inputs
                            code = $fgets(str, fd);
                            dummy = $sscanf(str, "%d", data_from_file);
                            samples[i] = data_from_file;
                            // $monitor("Hello World in loop");
                            // $monitor($sformatf("sample is %1d", data_from_file));
                            $fwrite(f,$sformatf("%1d\n",outsample[i]));
                            #0.01;
                        end
                        $fwrite(fdebug,$sformatf("%1d\n",0));
                        $fwrite(fdebug,$sformatf("%1d\n",0));
                        $fwrite(fdebug,$sformatf("%1d\n",0));
                        $fwrite(fdebug,$sformatf("%1d\n",0));
                        $fwrite(fdebug,$sformatf("%1d\n",0));
                        $fwrite(fdebug,$sformatf("%1d\n",0));
                        $fwrite(fdebug,$sformatf("%1d\n",0));
                        $fwrite(fdebug,$sformatf("%1d\n",0));
                    end

                    // Biquad reset
                    bq_reset_reg = 1'b1;
                    for(int clocks=0;clocks<32;clocks++) begin
                        @(posedge aclk);
                        #0.01;
                    end
                    bq_reset_reg = 1'b0;

                    $fclose(fd);
                    $fclose(fdebug);
                    $fclose(f);

                    // SEND IN THE GAUSSIAN HANNING WINDOWS

                    for(int in_count=0; in_count<10; in_count = in_count+1) begin
                        
                        fd = $fopen($sformatf("freqs/inputs/gauss_input_%1d_sigma_hanning_clipped_%0d.dat", GAUSS_NOISE_SIZE, in_count),"r");
                        f = $fopen($sformatf("freqs/outputs/trigger_chain_output_gauss_%1d_trial_%0d_notch_%0d_MHz_%1d.txt", GAUSS_NOISE_SIZE, in_count, notch, Q), "w");
                        fdebug = $fopen($sformatf("freqs/outputs/trigger_chain_output_debug_gauss_%1d_trial_%0d_notch_%0d_MHz_%1d.txt", GAUSS_NOISE_SIZE, in_count, notch, Q), "w");
                        $monitor($sformatf("freqs/outputs/trigger_chain_output_gauss_%1d_trial_%0d_notch_%0d_MHz_%1d.txt", GAUSS_NOISE_SIZE, in_count, notch,Q));

                        code = 1;

                        for(int clocks=0;clocks<10007;clocks++) begin // We are expecting 80064 samples, cut the end
                            @(posedge aclk);
                            #0.01;
                            for (int i=0; i<8; i++) begin
                                // Get the next inputs
                                code = $fgets(str, fd);
                                dummy = $sscanf(str, "%d", data_from_file);
                                samples[i] = data_from_file;
                                $fwrite(f,$sformatf("%1d\n",outsample[i]));
                                #0.01;
                            end
                            $fwrite(fdebug,$sformatf("%1d\n",0));
                            $fwrite(fdebug,$sformatf("%1d\n",0));
                            $fwrite(fdebug,$sformatf("%1d\n",0));
                            $fwrite(fdebug,$sformatf("%1d\n",0));
                            $fwrite(fdebug,$sformatf("%1d\n",0));
                            $fwrite(fdebug,$sformatf("%1d\n",0));
                            $fwrite(fdebug,$sformatf("%1d\n",0));
                            $fwrite(fdebug,$sformatf("%1d\n",0));
                        end

                        // Biquad reset
                        bq_reset_reg = 1'b1;
                        for(int clocks=0;clocks<32;clocks++) begin
                            @(posedge aclk);
                            #0.01;
                        end
                        bq_reset_reg = 1'b0;
                        $fclose(fd);
                        $fclose(fdebug);
                        $fclose(f);
                    end
                end
            end
        end else begin : DEFAULT_RUN
            $monitor("THIS_DESIGN set to something other");       
        end
    end
    
endmodule
