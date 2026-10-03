`timescale 1ns / 1ps
`include "interfaces.vh"
`ifndef DLYFF
`define DLYFF #0.1
`endif

// Flight trigger chain testbench matching SURFv6 configuration (biquads bypassed).
// Uses trigger_chain_wrapper_1500: LPF_v4 -> matched_filter_v3_1500 -> (bypass) -> upsample -> AGC
// AGC_CONTROL="TRUE" means the AGC loop is hardware-managed (no manual PID needed).
// Writes per-stage output files for: LPF, matched filter, pre-AGC (upsample), and AGC.
module flight_trigger_chain_tb;

    parameter THIS_STIM = "FILE"; // "FILE" or "GAUSS_RAND"

    // SURFv6-matching chain parameters (biquads bypassed as in flight)
    parameter AGC_TIMESCALE_REDUCTION_BITS = 4; // SURFv6 uses 1; 4 speeds up simulation
    parameter HDL_FILTER_VERSION = "V4";
    parameter AGC_CONTROL = "TRUE";
    parameter PIPE_TO_FILTER = "TRUE";

    localparam int GAUSS_NOISE_SIZE = 80;
    localparam int NUM_TRIALS = 10;
    localparam int CAPTURE_CLOCKS = 10007;

    // Gaussian random parameters (GAUSS_RAND mode)
    int seed = 1;
    int stim_sdev = 200;

    // Clocks: 100 MHz WB, 375 MHz aclk (SURFv6 rates)
    wire wbclk;
    wire aclk;
    tb_rclk #(.PERIOD(10.0)) u_wbclk(.clk(wbclk));
    tb_rclk #(.PERIOD(2.667)) u_aclk(.clk(aclk));

    // ===== Wishbone interface for Biquad (tied off — bypassed) =====
    `DEFINE_WB_IF( wb_bq_ , 8, 32);
    assign wb_bq_cyc_o = 1'b0;
    assign wb_bq_stb_o = 1'b0;
    assign wb_bq_we_o  = 1'b0;
    assign wb_bq_sel_o = 4'b0;
    assign wb_bq_dat_o = 32'b0;
    assign wb_bq_adr_o = 8'b0;

    // ===== Wishbone interface for AGC Controller =====
    reg agc_use = 0;
    reg agc_wr = 0;
    reg [7:0] agc_address = 8'h0;
    reg [31:0] agc_data_out = 32'h0;
    `DEFINE_WB_IF( wb_agc_ , 8, 32);
    assign wb_agc_cyc_o = agc_use;
    assign wb_agc_stb_o = agc_use;
    assign wb_agc_we_o  = agc_wr;
    assign wb_agc_sel_o = {4{agc_use}};
    assign wb_agc_dat_o = agc_data_out;
    assign wb_agc_adr_o = agc_address;

    task do_read_agc;
        input [7:0] in_addr;
        output [31:0] out_data;
        begin
            agc_address = in_addr;
            #1 agc_use = 1; agc_wr = 0;
            @(posedge wbclk);
            while (!wb_agc_ack_i) #1 @(posedge wbclk);
            out_data = wb_agc_dat_i;
            #1 agc_use = 0;
        end
    endtask

    // ===== Input samples (8 x 12-bit at 3 GHz equivalent) =====
    reg [11:0] samples [7:0];
    initial for (int i = 0; i < 8; i = i + 1) samples[i] <= 0;
    wire [95:0] sample_arr = { samples[7], samples[6], samples[5], samples[4],
                               samples[3], samples[2], samples[1], samples[0] };

    // ===== Output samples (8 x 5-bit after AGC) =====
    wire [4:0] outsample [7:0];
    wire [39:0] outsample_arr;
    generate
        genvar k;
        for (k = 0; k < 8; k = k + 1) begin : DEVEC
            assign outsample[k] = outsample_arr[5*k +: 5];
        end
    endgenerate

    // ===== Chain stage probes (hierarchical references into DUT) =====

    // LPF output: 8 x 12-bit (3 GHz rate)
    wire [95:0] lpf_probe;
    assign lpf_probe = u_chain.lpf_out;
    wire [11:0] lpf_sample [7:0];
    generate
        genvar lp;
        for (lp = 0; lp < 8; lp = lp + 1) begin : DEVEC_LPF
            assign lpf_sample[lp] = lpf_probe[12*lp +: 12];
        end
    endgenerate

    // Matched filter output: 4 x 12-bit (1500 MHz rate)
    wire [47:0] matched_probe;
    assign matched_probe = u_chain.match_out;
    wire [11:0] matched_sample [3:0];
    generate
        genvar m;
        for (m = 0; m < 4; m = m + 1) begin : DEVEC_MATCH
            assign matched_sample[m] = matched_probe[12*m +: 12];
        end
    endgenerate

    // Pre-AGC (after upsample): 8 x 12-bit (3 GHz rate)
    wire [95:0] pre_agc_probe;
    assign pre_agc_probe = u_chain.to_agc;
    wire [11:0] pre_agc_sample [7:0];
    generate
        genvar j;
        for (j = 0; j < 8; j = j + 1) begin : DEVEC_PREAGC
            assign pre_agc_sample[j] = pre_agc_probe[12*j +: 12];
        end
    endgenerate

    // ===== Reset =====
    reg reset_reg = 1'b0;
    reg agc_reset_reg = 1'b0;

    // ===== DUT: trigger_chain_wrapper_1500 (SURFv6 flight chain, biquads bypassed) =====
    trigger_chain_wrapper_1500 #(
        .AGC_TIMESCALE_REDUCTION_BITS(AGC_TIMESCALE_REDUCTION_BITS),
        .USE_BIQUADS("FALSE"),
        .HDL_FILTER_VERSION(HDL_FILTER_VERSION),
        .AGC_CONTROL(AGC_CONTROL),
        .PIPE_TO_FILTER(PIPE_TO_FILTER),
        .WBCLKTYPE("PSCLK"),
        .CLKTYPE("ACLK")
    ) u_chain (
        .wb_clk_i(wbclk),
        .wb_rst_i(1'b0),
        `CONNECT_WBS_IFM( wb_bq_ , wb_bq_ ),
        `CONNECT_WBS_IFM( wb_agc_controller_ , wb_agc_ ),
        .reset_i(reset_reg),
        .agc_reset_i(agc_reset_reg),
        .aclk(aclk),
        .notch_update_i(1'b0),
        .notch0_byp_i(6'b0),
        .notch1_byp_i(6'b0),
        .dat_i(sample_arr),
        .dat_o(outsample_arr)
    );

    // ===== File descriptors =====
    int fd;
    int f_lpf, f_matched, f_pre_agc, f_agc;
    int code, dummy, data_from_file;
    reg [8*10:1] str;
    int stim_val;
    reg [11:0] stim_vals [7:0];

    // ===== Stimulus =====
    initial begin : STIM_LOOP
        #500; // Let clocks settle and AGC boot delay begin

        if (THIS_STIM == "FILE") begin : FILE_RUN

            // ---- Impulse response test ----
            $display("[%0t] Sending impulse", $time);
            fd        = $fopen("freqs/inputs/pulse_input_height_512_clipped.dat", "r");
            f_lpf     = $fopen("freqs/outputs/flight_pulse_lpf.dat", "w");
            f_matched = $fopen("freqs/outputs/flight_pulse_matched.dat", "w");
            f_pre_agc = $fopen("freqs/outputs/flight_pulse_preagc.dat", "w");
            f_agc     = $fopen("freqs/outputs/flight_pulse_agc.dat", "w");

            for (int clocks = 0; clocks < CAPTURE_CLOCKS; clocks++) begin
                @(posedge aclk);
                #0.01;
                for (int i = 0; i < 8; i++) begin
                    code = $fgets(str, fd);
                    dummy = $sscanf(str, "%d", data_from_file);
                    samples[i] = data_from_file;
                    $fwrite(f_lpf,     "%1d\n", $signed(lpf_sample[i]));
                    $fwrite(f_pre_agc, "%1d\n", $signed(pre_agc_sample[i]));
                    $fwrite(f_agc,     "%1d\n", outsample[i]);
                    #0.01;
                end
                for (int i = 0; i < 4; i++) begin
                    $fwrite(f_matched, "%1d\n", $signed(matched_sample[i]));
                end
            end

            $fclose(fd);
            $fclose(f_lpf);
            $fclose(f_matched);
            $fclose(f_pre_agc);
            $fclose(f_agc);

            // Brief reset between impulse and Gaussian tests
            reset_reg = 1'b1;
            repeat (32) @(posedge aclk);
            reset_reg = 1'b0;

            // ---- Hanning-windowed Gaussian noise trials ----
            for (int trial = 0; trial < NUM_TRIALS; trial = trial + 1) begin
                $display("[%0t] Gaussian trial %0d/%0d", $time, trial, NUM_TRIALS);

                fd        = $fopen($sformatf("freqs/inputs/gauss_input_%1d_sigma_hanning_clipped_%0d.dat",
                                              GAUSS_NOISE_SIZE, trial), "r");
                f_lpf     = $fopen($sformatf("freqs/outputs/flight_gauss_%1d_trial_%0d_lpf.dat",
                                              GAUSS_NOISE_SIZE, trial), "w");
                f_matched = $fopen($sformatf("freqs/outputs/flight_gauss_%1d_trial_%0d_matched.dat",
                                              GAUSS_NOISE_SIZE, trial), "w");
                f_pre_agc = $fopen($sformatf("freqs/outputs/flight_gauss_%1d_trial_%0d_preagc.dat",
                                              GAUSS_NOISE_SIZE, trial), "w");
                f_agc     = $fopen($sformatf("freqs/outputs/flight_gauss_%1d_trial_%0d_agc.dat",
                                              GAUSS_NOISE_SIZE, trial), "w");

                for (int clocks = 0; clocks < CAPTURE_CLOCKS; clocks++) begin
                    @(posedge aclk);
                    #0.01;
                    for (int i = 0; i < 8; i++) begin
                        code = $fgets(str, fd);
                        dummy = $sscanf(str, "%d", data_from_file);
                        samples[i] = data_from_file;
                        $fwrite(f_lpf,     "%1d\n", $signed(lpf_sample[i]));
                        $fwrite(f_pre_agc, "%1d\n", $signed(pre_agc_sample[i]));
                        $fwrite(f_agc,     "%1d\n", outsample[i]);
                        #0.01;
                    end
                    for (int i = 0; i < 4; i++) begin
                        $fwrite(f_matched, "%1d\n", $signed(matched_sample[i]));
                    end
                end

                // Reset between trials
                reset_reg = 1'b1;
                repeat (32) @(posedge aclk);
                reset_reg = 1'b0;

                $fclose(fd);
                $fclose(f_lpf);
                $fclose(f_matched);
                $fclose(f_pre_agc);
                $fclose(f_agc);
            end

            $display("[%0t] FILE stimulus complete.", $time);
            $finish;

        end else if (THIS_STIM == "GAUSS_RAND") begin : GAUSS_RAND_RUN

            $display("[%0t] Beginning continuous random Gaussian stimulus", $time);
            forever begin
                @(posedge aclk);
                #0.01;
                for (int i = 0; i < 8; i++) begin
                    do begin
                        stim_val = $dist_normal(seed, 0, stim_sdev);
                    end while (stim_val > 2047 || stim_val < -2048);
                    stim_vals[i] = stim_val;
                end
                samples = stim_vals;
            end

        end else begin
            $display("ERROR: Unknown THIS_STIM: %s", THIS_STIM);
            $finish;
        end
    end

endmodule
