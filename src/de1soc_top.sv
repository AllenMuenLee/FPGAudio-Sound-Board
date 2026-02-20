`timescale 1ns/1ps
module de1soc_wrapper (
    input         CLOCK_50,
    input  [9:0]  SW,
    input  [3:0]  KEY,

    inout         PS2_CLK,
    inout         PS2_DAT,

    output [6:0]  HEX5,
    output [6:0]  HEX4,
    output [6:0]  HEX3,
    output [6:0]  HEX2,
    output [6:0]  HEX1,
    output [6:0]  HEX0,

    output [9:0]  LEDR,

    output [7:0]  VGA_R,
    output [7:0]  VGA_G,
    output [7:0]  VGA_B,
    output        VGA_HS,
    output        VGA_VS,
    output        VGA_BLANK_N,
    output        VGA_SYNC_N,
    output        VGA_CLK,

    // Audio Codec Interface
    input         AUD_ADCDAT,
    input         AUD_ADCLRCK,
    input         AUD_BCLK,
    output        AUD_DACDAT,
    input         AUD_DACLRCK,
    output        AUD_XCK,

    // I2C Configuration Interface
    output        FPGA_I2C_SCLK,
    inout         FPGA_I2C_SDAT
);

    // Default Assignments

    // LEDs off (commented out - driven by audio VU meter)
    // assign LEDR = 10'b0;

    // HEX displays off (active-low)
    assign HEX0 = 7'b1111111;
    assign HEX1 = 7'b1111111;
    assign HEX2 = 7'b1111111;
    assign HEX3 = 7'b1111111;

    // VGA outputs black / inactive
    assign VGA_R = 8'b0;
    assign VGA_G = 8'b0;
    assign VGA_B = 8'b0;

    assign VGA_HS      = 1'b1;
    assign VGA_VS      = 1'b1;
    assign VGA_BLANK_N = 1'b1;
    assign VGA_SYNC_N  = 1'b0;
    assign VGA_CLK     = CLOCK_50;

    // ========================================================================
    // Audio System Instantiation
    // ========================================================================
    de1soc_audio_top audio_system (
        .CLOCK_50(CLOCK_50),
        .KEY(KEY),
        .SW(SW),
        .LEDR(LEDR),
        .AUD_ADCDAT(AUD_ADCDAT),
        .AUD_ADCLRCK(AUD_ADCLRCK),
        .AUD_BCLK(AUD_BCLK),
        .AUD_DACDAT(AUD_DACDAT),
        .AUD_DACLRCK(AUD_DACLRCK),
        .AUD_XCK(AUD_XCK),
        .FPGA_I2C_SCLK(FPGA_I2C_SCLK),
        .FPGA_I2C_SDAT(FPGA_I2C_SDAT)
    );

endmodule
