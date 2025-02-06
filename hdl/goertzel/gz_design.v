//////////////////////////////////////////////////////////////////////////////////
// Company: the Ohio State University
// Engineer: Connor Fricke (cd.fricke23@gmail.com)
// Create Date: 10/24/2024 02:57:10 PM
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps
`include "interfaces.vh"

module gz_design(
        input aclk,
        input arst,

        /* ADC0 Input */
        input [127:0] s0_axis_tdata,
        input         s0_axis_tvalid,
        output        s0_axis_tready,

        /* ADC1 Input */
        // Currently we are overriding the ADC1->BUF1 channel by feeding Goertzel data from ADC0->BUF1
        // i.e. this interface doesn't connect to anything
        input [127:0] s1_axis_tdata,
        input         s1_axis_tvalid,
        output        s1_axis_tready,

        /* ADC2 Input */
        input [127:0] s2_axis_tdata,
        input         s2_axis_tvalid,
        output        s2_axis_tready,

        /* ADC3 Input */
        input [127:0] s3_axis_tdata,
        input         s3_axis_tvalid,
        output        s3_axis_tready,
    
        /* BUF0 Output */
        output [127:0] m0_axis_tdata,
        output         m0_axis_tvalid,
        input          m0_axis_tready,      // assume == 1, buffer should always be ready to read

        /* BUF1 Output (goertzel_IIR data) */
        output [127:0] m1_axis_tdata,
        output         m1_axis_tvalid,
        input          m1_axis_tready,      // assume == 1, buffer should always be ready to read

        /* BUF2 Output */
        output [127:0] m2_axis_tdata,
        output         m2_axis_tvalid,
        input          m2_axis_tready,      // assume == 1, buffer should always be ready to read

        /* BUF3 Output */
        output [127:0] m3_axis_tdata,
        output         m3_axis_tvalid,     
        input          m3_axis_tready       // assume == 1, buffer should always be ready to read

    );

    /* ADC0 -> BUF0 */
    assign m0_axis_tdata = s0_axis_tdata;
    assign m0_axis_tvalid = s0_axis_tvalid;
    assign s0_axis_tready = 1'b1;

    /* ADC1 -> NOT CONNECTED */
    assign s1_axis_tready = 1'b0;

    /* ADC2 -> BUF2 */
    assign m2_axis_tdata = s2_axis_tdata;
    assign m2_axis_tvalid = s2_axis_tvalid;
    assign s2_axis_tready = 1'b1;

    /* ADC3 -> BUF3 */
    assign m3_axis_tdata = s3_axis_tdata;
    assign m3_axis_tvalid = s3_axis_tvalid;
    assign s3_axis_tready = 1'b1;

    /* GOERTZEL DESIGN */
    /* ADC0 -> GZ -> BUF1 */

    localparam [7:0] IW = 12;     // signal width
    localparam [7:0] N = 126;     // num samples (window length)
    localparam [7:0] OW = 20;     // output width (for real and imag component separately)
    localparam [7:0] SW = 16;     // buffer stream sample width

    reg enable = 1'b0;
    always @ (posedge aclk) enable <= ~enable;

    wire [(2*OW-1):0] pre_tdata;
    wire [(SW-1):0] Xk_re, Xk_im;

    goertzel_IIR #(.IW(IW), .N(N), .OW(OW)) wave_detector(
        .i_clk          (aclk),
        .i_clken        (enable),
        .i_rst          (arst),
        .s_axis_tdata   (s0_axis_tdata[15:4]),   // only want top 12 MSBs of a single sample
        .s_axis_tvalid  (s0_axis_tvalid),
        .s_axis_tready  (),
        .m_axis_tdata   (pre_tdata),
        .m_axis_tvalid  (m1_axis_tvalid),
        .m_axis_tready  (m1_axis_tready)
    );

    /* PROCESS PRE-DATA FOR BUFFER 1 STREAM */
    assign Xk_re = pre_tdata[(2*OW-1):(2*OW-SW)];
    assign Xk_im = pre_tdata[(OW-1):(OW-SW)];
    assign m1_axis_tdata = { {(128-(2*SW)){1'b0}}, Xk_re, Xk_im };

endmodule
