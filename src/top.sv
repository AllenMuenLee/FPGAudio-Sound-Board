// Auto-merged: shared RAM refactor

// ===== BEGIN util_digital.v =====

// ============================================================================
// Digital Simulator Utility Modules - Shared Components
// ============================================================================

module DIG_Counter_Nbit
#(
    parameter Bits = 2
)
(
    output [(Bits-1):0] out,
    output ovf,
    input C,
    input en,
    input clr
);
    reg [(Bits-1):0] count;
    always @ (posedge C) begin
        if (clr)
            count <= 'h0;
        else if (en)
            count <= count + 1'b1;
    end
    assign out = count;
    assign ovf = en? &count : 1'b0;
    initial begin
        count = 'h0;
    end
endmodule

module DIG_RAMDualAccess
#(
    parameter Bits = 8,
    parameter AddrBits = 4
)
(
    input C,
    input ld,
    input [(AddrBits-1):0] \1A ,
    input [(AddrBits-1):0] \2A ,
    input [(Bits-1):0] \1Din ,
    input str,
    output [(Bits-1):0] \1D ,
    output [(Bits-1):0] \2D
);
    reg [(Bits-1):0] memory [0:((1 << AddrBits)-1)];
    assign \1D = ld? memory[\1A ] : {Bits{1'b0}};
    assign \2D = memory[\2A ];
    always @ (posedge C) begin
        if (str)
            memory[\1A ] <= \1Din ;
    end
endmodule

module DIG_RAMDualPort
#(
    parameter Bits = 16,
    parameter AddrBits = 4
)
(
    input [(AddrBits-1):0] A,
    input [(Bits-1):0] Din,
    input str,
    input C,
    input ld,
    output [(Bits-1):0] D
);
    reg [(Bits-1):0] memory[0:((1 << AddrBits) - 1)];
    assign D = ld? memory[A] : {Bits{1'b0}};
    always @ (posedge C) begin
        if (str)
            memory[A] <= Din;
    end
endmodule

module DIG_Add
#(
    parameter Bits = 1
)
(
    input [(Bits-1):0] a,
    input [(Bits-1):0] b,
    input c_i,
    output [(Bits - 1):0] s,
    output c_o
);
    wire [Bits:0] temp;
    assign temp = a + b + {{Bits{1'b0}}, c_i};
    assign s = temp [(Bits-1):0];
    assign c_o = temp[Bits];
endmodule

module DIG_Sub
#(
    parameter Bits = 1
)
(
    input [(Bits-1):0] a,
    input [(Bits-1):0] b,
    input c_i,
    output [(Bits-1):0] s,
    output c_o
);
    wire [Bits:0] temp;
    assign temp = a - b - {{Bits{1'b0}}, c_i};
    assign s = temp[(Bits-1):0];
    assign c_o = temp[Bits];
endmodule

module DIG_Register_BUS #(
    parameter Bits = 1
)
(
    input C,
    input en,
    input [(Bits - 1):0]D,
    output [(Bits - 1):0]Q
);
    reg [(Bits - 1):0] state = 'h0;
    assign Q = state;
    always @ (posedge C) begin
        if (en)
            state <= D;
    end
endmodule

module DIG_Neg #(
    parameter Bits = 1
)
(
    input signed [(Bits-1):0] in,
    output signed [(Bits-1):0] out
);
    assign out = -in;
endmodule

module Mux_2x1_NBits #(
    parameter Bits = 2
)
(
    input [0:0] sel,
    input [(Bits - 1):0] in_0,
    input [(Bits - 1):0] in_1,
    output reg [(Bits - 1):0] out
);
    always @ (*) begin
        case (sel)
            1'h0: out = in_0;
            1'h1: out = in_1;
            default: out = 'h0;
        endcase
    end
endmodule

module CompUnsigned #(
    parameter Bits = 1
)
(
    input [(Bits -1):0] a,
    input [(Bits -1):0] b,
    output \> ,
    output \= ,
    output \<
);
    assign \> = a > b;
    assign \= = a == b;
    assign \< = a < b;
endmodule

module DIG_Mul_unsigned #(
    parameter Bits = 1
)
(
    input [(Bits-1):0] a,
    input [(Bits-1):0] b,
    output [(Bits*2-1):0] mul
);
    assign mul = a * b;
endmodule

module DIG_BitExtender #(
    parameter inputBits = 2,
    parameter outputBits = 4
)
(
    input [(inputBits-1):0] in,
    output [(outputBits - 1):0] out
);
    assign out = {{(outputBits - inputBits){in[inputBits - 1]}}, in};
endmodule

// ===== END util_digital.v =====


// ===== BEGIN effect_noisegate.v =====

// ============================================================================
// Noise Gate Effect Module
// ============================================================================
// Implements adaptive noise gate with attack/release thresholds.
// Pure combinational/sequential logic - no RAM required.
// ============================================================================

module noise_gate (
    input wire reset,
    input clk,
    input signed [15:0] audio_in,
    output [15:0] audio_out
);
    wire s0;
    wire [15:0] s1;
    wire [15:0] s2;
    wire s3;
    wire s4;
    wire [10:0] s5;
    wire [10:0] s6;
    reg s7;
    wire [10:0] s8;
    wire [10:0] s9;
    wire [15:0] s10;
    wire [31:0] s11;
    wire s12;
    wire [10:0] s13;
    wire s14;
    wire unused_comp_eq0, unused_comp_lt0, unused_comp_gt1, unused_comp_eq1;
    wire unused_comp_eq2, unused_comp_lt2, unused_comp_gt3, unused_comp_eq3;
    wire unused_add_co;

    DIG_Neg #(.Bits(16)) DIG_Neg_i0 (.in(audio_in), .out(s1));
    assign s0 = audio_in[15];
    Mux_2x1_NBits #(.Bits(16)) Mux_2x1_NBits_i1 (.sel(s0), .in_0(audio_in), .in_1(s1), .out(s2));

    // Attack threshold
    CompUnsigned #(.Bits(16)) CompUnsigned_i2 (
        .a(s2), .b(16'b1111101000),
        .\> (s3), .\= (unused_comp_eq0), .\< (unused_comp_lt0)
    );
    // Release threshold
    CompUnsigned #(.Bits(16)) CompUnsigned_i3 (
        .a(s2), .b(16'b111110100),
        .\> (unused_comp_gt1), .\= (unused_comp_eq1), .\< (s4)
    );

    DIG_Mul_unsigned #(.Bits(16)) DIG_Mul_unsigned_i4 (.a(s10), .b(s2), .mul(s11));

    // Gate state machine
    always @(posedge clk or posedge reset) begin
        if (reset) s7 <= 1'b0;
        else begin
            if (s3)      s7 <= 1'b1;
            else if (s4) s7 <= 1'b0;
        end
    end

    Mux_2x1_NBits #(.Bits(11)) Mux_2x1_NBits_i5 (
        .sel(s7), .in_0(11'b1010), .in_1(11'b11111110110), .out(s8)
    );

    assign audio_out = s11[25:10];

    DIG_Add #(.Bits(11)) DIG_Add_i6 (
        .a(s6), .b(s8), .c_i(1'b0), .s(s9), .c_o(unused_add_co)
    );

    DIG_BitExtender #(.inputBits(11), .outputBits(16)) DIG_BitExtender_i7 (.in(s9), .out(s10));

    // Check gain max
    CompUnsigned #(.Bits(11)) CompUnsigned_i8 (
        .a(11'b10000000000), .b(s9),
        .\> (s12), .\= (unused_comp_eq2), .\< (unused_comp_lt2)
    );
    Mux_2x1_NBits #(.Bits(11)) Mux_2x1_NBits_i9 (
        .sel(s12), .in_0(11'b10000000000), .in_1(s9), .out(s13)
    );

    // Check gain min
    CompUnsigned #(.Bits(11)) CompUnsigned_i10 (
        .a(11'b1100110), .b(s13),
        .\> (unused_comp_gt3), .\= (unused_comp_eq3), .\< (s14)
    );
    Mux_2x1_NBits #(.Bits(11)) Mux_2x1_NBits_i11 (
        .sel(s14), .in_0(11'b1100110), .in_1(s13), .out(s5)
    );

    DIG_Register_BUS #(.Bits(11)) DIG_Register_BUS_i12 (
        .D(s5), .C(clk), .en(1'b1), .Q(s6)
    );
endmodule

// ===== END effect_noisegate.v =====


// ===== BEGIN effect_muffled.v =====

// ============================================================================
// Muffled Effect Module
// ============================================================================
// Cascaded IIR lowpass filter. Pure logic - no RAM required.
// ============================================================================

module muffled_effect (
    input [15:0] audio_in,
    input wire clk,
    input wire reset,
    output [15:0] audio_out
);
    wire [15:0] y_1;
    wire [15:0] s0;
    wire [15:0] y_2;
    wire [15:0] s1;
    wire [15:0] s2;
    wire [15:0] s3;
    wire [15:0] s4;
    wire [15:0] s5;
    wire [15:0] s6;
    reg s7;
    wire s8;
    wire s9;
    wire unused_sub0_co, unused_sub1_co;
    wire unused_add0_co, unused_add1_co, unused_add2_co;

    DIG_Sub #(.Bits(16)) DIG_Sub_i0 (
        .a(audio_in[15:0]), .b(y_1[15:0]), .c_i(1'b0), .s(s0), .c_o(unused_sub0_co)
    );
    assign s7 = s0[15];
    assign s2[11:0] = s0[15:4];
    assign s2[12] = s7; assign s2[13] = s7; assign s2[14] = s7; assign s2[15] = s7;

    DIG_Add #(.Bits(16)) DIG_Add_i1 (
        .a(s2[15:0]), .b(y_1[15:0]), .c_i(1'b0), .s(s3), .c_o(unused_add0_co)
    );
    DIG_Register_BUS #(.Bits(16)) DIG_Register_BUS_i2 (
        .D(s3), .C(clk), .en(1'b1), .Q(y_1)
    );

    DIG_Sub #(.Bits(16)) DIG_Sub_i3 (
        .a(y_1[15:0]), .b(y_2[15:0]), .c_i(1'b0), .s(s1), .c_o(unused_sub1_co)
    );
    assign s8 = s1[15];
    assign s4[11:0] = s1[15:4];
    assign s4[12] = s8; assign s4[13] = s8; assign s4[14] = s8; assign s4[15] = s8;

    DIG_Add #(.Bits(16)) DIG_Add_i4 (
        .a(s4[15:0]), .b(y_2[15:0]), .c_i(1'b0), .s(s5), .c_o(unused_add1_co)
    );
    DIG_Register_BUS #(.Bits(16)) DIG_Register_BUS_i5 (
        .D(s5), .C(clk), .en(1'b1), .Q(y_2)
    );

    assign s9 = y_2[15];
    assign s6[11:0] = y_2[15:4];
    assign s6[12] = s9; assign s6[13] = s9; assign s6[14] = s9; assign s6[15] = s9;

    DIG_Add #(.Bits(16)) DIG_Add_i6 (
        .a(s6[15:0]), .b(y_2[15:0]), .c_i(1'b0), .s(audio_out), .c_o(unused_add2_co)
    );
endmodule

// ===== END effect_muffled.v =====


// ===== BEGIN audio_processor.sv =====

// ============================================================================
// Audio Processor - Single Shared RAM Architecture
// ============================================================================
// High pitch, low pitch, and reverb all share one 16K x 16-bit delay RAM.
// The read pointer accumulator step is muxed based on effect_select.
// Muffled and noise gate are pure logic with no RAM.
//
// Effect select (SW[2:0]):
//   000 = Noise Gate  (no RAM)
//   001 = High Pitch  (RAM read pointer advances at 2x write speed)
//   010 = Low Pitch   (RAM read pointer advances at 0.5x write speed)
//   011 = Reverb      (RAM read at 1x with feedback mix)
//   100 = Muffled     (no RAM, cascaded IIR lowpass)
//   default = Bypass
//
// audio_valid must be a single-cycle pulse at 48kHz (from i2s_interface).
// RAM pointers only advance on audio_valid so delay times are accurate.
// ============================================================================

module audio_processor (
    input             clk,
    input             reset,
    input      [15:0] audio_in,
    input      [9:0]  SW,
    input             audio_valid,    // 48kHz pulse from I2S interface
    output reg [15:0] audio_out
);

    wire [2:0] effect_select = SW[2:0];

    // ========================================================================
    // Shared Delay RAM (16K x 16-bit = 256KB, one copy instead of three)
    // ========================================================================
    reg  [13:0] wr_ptr;           // Write pointer
    reg  [17:0] rd_accumulator;   // Fractional read accumulator (18-bit fixed point)
    wire [13:0] rd_ptr = rd_accumulator[17:4];  // Integer part of read address

    reg  [15:0] ram_din;
    wire [15:0] ram_dout;

    DIG_RAMDualAccess #(
        .Bits(16),
        .AddrBits(14)
    ) shared_ram (
        .C      (clk),
        .str    (audio_valid),    // Write only on new audio sample
        .ld     (1'b1),
        .\1A    (wr_ptr),
        .\1Din  (ram_din),
        .\1D    (),               // Port 1 read unused
        .\2A    (rd_ptr),
        .\2D    (ram_dout)
    );

    // ========================================================================
    // Read Step Mux
    // ========================================================================
    // Fixed-point step where bit 4 = integer 1.0 (i.e. 16 = 1x speed).
    //   32 = 2.0x -> reads faster -> pitch up
    //    8 = 0.5x -> reads slower -> pitch down
    //   16 = 1.0x -> simple delay  -> reverb
    reg [17:0] rd_step;
    always @(*) begin
        case (effect_select)
            3'b001:  rd_step = 18'd32;    // High pitch
            3'b010:  rd_step = 18'd8;     // Low pitch
            3'b011:  rd_step = 18'd16;    // Reverb (1:1 delay)
            default: rd_step = 18'd16;
        endcase
    end

    // ========================================================================
    // Pointer Update (audio rate only)
    // ========================================================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            wr_ptr         <= 14'd0;
            rd_accumulator <= 18'd0;
        end else if (audio_valid) begin
            wr_ptr         <= wr_ptr + 14'd1;
            rd_accumulator <= rd_accumulator + rd_step;
        end
    end

    // ========================================================================
    // Reverb Feedback and Output Mix
    // ========================================================================
    // Feedback: delayed signal attenuated by >>4 (1/16 volume) mixed into write
    // Output:   dry + delayed wet
    wire        fb_sign        = ram_dout[15];
    wire [15:0] reverb_feedback;
    assign reverb_feedback[11:0] = ram_dout[15:4];   // Arithmetic right shift by 4
    assign reverb_feedback[12]   = fb_sign;
    assign reverb_feedback[13]   = fb_sign;
    assign reverb_feedback[14]   = fb_sign;
    assign reverb_feedback[15]   = fb_sign;

    wire [15:0] reverb_write_data = audio_in + reverb_feedback;
    wire [15:0] reverb_out        = audio_in + ram_dout;

    // ========================================================================
    // RAM Write Data Mux
    // ========================================================================
    always @(*) begin
        case (effect_select)
            3'b011:  ram_din = reverb_write_data;  // Reverb: feedback into delay line
            default: ram_din = audio_in;           // Others: clean write
        endcase
    end

    // ========================================================================
    // Noise Gate (pure logic)
    // ========================================================================
    wire [15:0] noise_gate_out;
    noise_gate ng_inst (
        .clk      (clk),
        .reset    (reset),
        .audio_in (audio_in),
        .audio_out(noise_gate_out)
    );

    // ========================================================================
    // Muffled Effect (pure logic)
    // ========================================================================
    wire [15:0] muffled_out;
    muffled_effect muf_inst (
        .clk      (clk),
        .reset    (reset),
        .audio_in (audio_in),
        .audio_out(muffled_out)
    );

    // ========================================================================
    // Output Mux
    // ========================================================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            audio_out <= 16'd0;
        end else begin
            case (effect_select)
                3'b000:  audio_out <= noise_gate_out;
                3'b001:  audio_out <= ram_dout;       // High pitch
                3'b010:  audio_out <= ram_dout;       // Low pitch
                3'b011:  audio_out <= reverb_out;     // Reverb
                3'b100:  audio_out <= muffled_out;    // Muffled
                default: audio_out <= audio_in;       // Bypass
            endcase
        end
    end

endmodule

// ===== END audio_processor.sv =====


// ===== BEGIN audioprocessor_top.sv =====

// ============================================================================
// Top-Level System Integration
// ============================================================================

module de1soc_audio_top (
    input         CLOCK_50,
    input  [3:0]  KEY,
    input  [9:0]  SW,
    output [9:0]  LEDR,

    input         AUD_ADCDAT,
    input         AUD_ADCLRCK,
    input         AUD_BCLK,
    output        AUD_DACDAT,
    input         AUD_DACLRCK,
    output        AUD_XCK,

    output        FPGA_I2C_SCLK,
    inout         FPGA_I2C_SDAT
);

    wire reset;
    assign reset = ~KEY[0];

    // Audio master clock (~12.5MHz for WM8731)
    audio_clock clk_gen (
        .clk_50mhz(CLOCK_50),
        .reset    (reset),
        .aud_xck  (AUD_XCK)
    );

    // WM8731 I2C configuration
    wire config_done;
    wm8731_config codec_config (
        .clk        (CLOCK_50),
        .reset      (reset),
        .config_done(config_done),
        .i2c_sclk   (FPGA_I2C_SCLK),
        .i2c_sdat   (FPGA_I2C_SDAT)
    );

    // I2S audio interface
    wire [15:0] audio_in_left, audio_in_right;
    wire [15:0] audio_out_left, audio_out_right;
    wire        audio_valid;

    i2s_interface i2s (
        .clk         (CLOCK_50),
        .reset       (reset),
        .aud_adclrck (AUD_ADCLRCK),
        .aud_bclk    (AUD_BCLK),
        .aud_adcdat  (AUD_ADCDAT),
        .aud_dacdat  (AUD_DACDAT),
        .audio_out_l (audio_out_left),
        .audio_out_r (audio_out_right),
        .audio_in_l  (audio_in_left),
        .audio_in_r  (audio_in_right),
        .audio_valid (audio_valid)
    );

    // Left channel processor (shared RAM architecture)
    audio_processor dsp_left (
        .clk        (CLOCK_50),
        .reset      (reset),
        .audio_in   (audio_in_left),
        .SW         (SW),
        .audio_valid(audio_valid),
        .audio_out  (audio_out_left)
    );

    // Right channel processor (shared RAM architecture)
    audio_processor dsp_right (
        .clk        (CLOCK_50),
        .reset      (reset),
        .audio_in   (audio_in_right),
        .SW         (SW),
        .audio_valid(audio_valid),
        .audio_out  (audio_out_right)
    );

    // VU meter on processed left channel
    vu_meter audio_visualizer (
        .clk         (CLOCK_50),
        .reset       (reset),
        .audio_sample(audio_out_left),
        .led_out     (LEDR)
    );

endmodule

// ===== END audioprocessor_top.sv =====


// ===== BEGIN de1soc_top.sv =====

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

    input         AUD_ADCDAT,
    input         AUD_ADCLRCK,
    input         AUD_BCLK,
    output        AUD_DACDAT,
    input         AUD_DACLRCK,
    output        AUD_XCK,

    output        FPGA_I2C_SCLK,
    inout         FPGA_I2C_SDAT
);

    assign HEX0 = 7'b1111111;
    assign HEX1 = 7'b1111111;
    assign HEX2 = 7'b1111111;
    assign HEX3 = 7'b1111111;

    assign VGA_R       = 8'b0;
    assign VGA_G       = 8'b0;
    assign VGA_B       = 8'b0;
    assign VGA_HS      = 1'b1;
    assign VGA_VS      = 1'b1;
    assign VGA_BLANK_N = 1'b1;
    assign VGA_SYNC_N  = 1'b0;
    assign VGA_CLK     = CLOCK_50;

    de1soc_audio_top audio_system (
        .CLOCK_50    (CLOCK_50),
        .KEY         (KEY),
        .SW          (SW),
        .LEDR        (LEDR),
        .AUD_ADCDAT  (AUD_ADCDAT),
        .AUD_ADCLRCK (AUD_ADCLRCK),
        .AUD_BCLK    (AUD_BCLK),
        .AUD_DACDAT  (AUD_DACDAT),
        .AUD_DACLRCK (AUD_DACLRCK),
        .AUD_XCK     (AUD_XCK),
        .FPGA_I2C_SCLK(FPGA_I2C_SCLK),
        .FPGA_I2C_SDAT(FPGA_I2C_SDAT)
    );

endmodule

// ===== END de1soc_top.sv =====


// ===== BEGIN util_audioclock.v =====

`timescale 1ns/1ps
module audio_clock (
    input      clk_50mhz,
    input      reset,
    output reg aud_xck
);
    reg [2:0] counter;
    always @(posedge clk_50mhz or posedge reset) begin
        if (reset) begin
            counter <= 3'd0;
            aud_xck <= 1'b0;
        end else begin
            if (counter >= 3'd1) begin
                counter <= 3'd0;
                aud_xck <= ~aud_xck;
            end else begin
                counter <= counter + 1'd1;
            end
        end
    end
endmodule

// ===== END util_audioclock.v =====


// ===== BEGIN util_vumeter.v =====

`timescale 1ns/1ps
module vu_meter (
    input             clk,
    input             reset,
    input      [15:0] audio_sample,
    output reg [9:0]  led_out
);
    wire [15:0] abs_sample;
    assign abs_sample = audio_sample[15] ? (~audio_sample + 1'b1) : audio_sample;

    wire [3:0] current_level;
    assign current_level = abs_sample[15:12];

    reg [3:0]  peak_level;
    reg [23:0] decay_counter;
    localparam DECAY_TIME = 24'd16_777_215;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            peak_level    <= 4'd0;
            decay_counter <= 24'd0;
            led_out       <= 10'd0;
        end else begin
            if (current_level > peak_level) begin
                peak_level    <= current_level;
                decay_counter <= DECAY_TIME;
            end else if (decay_counter > 0) begin
                decay_counter <= decay_counter - 1'b1;
            end else begin
                if (peak_level > 0)
                    peak_level <= peak_level - 1'b1;
                decay_counter <= DECAY_TIME;
            end

            case (peak_level)
                4'd0:    led_out <= 10'b0000000000;
                4'd1:    led_out <= 10'b0000000001;
                4'd2:    led_out <= 10'b0000000011;
                4'd3:    led_out <= 10'b0000000111;
                4'd4:    led_out <= 10'b0000001111;
                4'd5:    led_out <= 10'b0000011111;
                4'd6:    led_out <= 10'b0000111111;
                4'd7:    led_out <= 10'b0001111111;
                4'd8:    led_out <= 10'b0011111111;
                4'd9:    led_out <= 10'b0111111111;
                default: led_out <= 10'b1111111111;
            endcase
        end
    end
endmodule

// ===== END util_vumeter.v =====


// ===== BEGIN wm8731_config.v =====

`timescale 1ns/1ps
module wm8731_config (
    input      clk,
    input      reset,
    output reg config_done,
    output     i2c_sclk,
    inout      i2c_sdat
);
    localparam WM8731_ADDR = 7'b0011010;
    localparam NUM_REGS = 10;

    reg [15:0] config_data [0:NUM_REGS-1];
    reg [3:0]  reg_index;
    reg        i2c_start;
    wire       i2c_ready;

    initial begin
        config_data[0] = 16'b0001111_000000000;  // R15: Reset
        config_data[1] = 16'b0000000_010010111;  // R0:  Left Line In
        config_data[2] = 16'b0000001_010010111;  // R1:  Right Line In
        config_data[3] = 16'b0000010_001111001;  // R2:  Left Headphone Out
        config_data[4] = 16'b0000011_001111001;  // R3:  Right Headphone Out
        config_data[5] = 16'b0000100_000010010;  // R4:  Analog Path
        config_data[6] = 16'b0000101_000000000;  // R5:  Digital Path
        config_data[7] = 16'b0000110_000000000;  // R6:  Power Down
        config_data[8] = 16'b0000111_001000010;  // R7:  Interface Format (I2S, 16-bit, master)
        config_data[9] = 16'b0001000_000000000;  // R8:  Sampling (48kHz)
    end

    localparam IDLE  = 2'd0;
    localparam WAIT  = 2'd1;
    localparam SEND  = 2'd2;
    localparam DELAY = 2'd3;

    reg [1:0]  state;
    reg [19:0] delay_cnt;

    i2c_controller i2c_ctrl (
        .clk          (clk),
        .reset        (reset),
        .start        (i2c_start),
        .device_addr  (WM8731_ADDR),
        .register_data(config_data[reg_index]),
        .ready        (i2c_ready),
        .i2c_sclk     (i2c_sclk),
        .i2c_sdat     (i2c_sdat)
    );

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state       <= IDLE;
            reg_index   <= 4'd0;
            i2c_start   <= 1'b0;
            config_done <= 1'b0;
            delay_cnt   <= 20'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (i2c_ready) begin
                        state     <= DELAY;
                        delay_cnt <= 20'd50000;
                    end
                end
                DELAY: begin
                    if (delay_cnt > 0) delay_cnt <= delay_cnt - 1'd1;
                    else               state <= SEND;
                end
                SEND: begin
                    i2c_start <= 1'b1;
                    state     <= WAIT;
                end
                WAIT: begin
                    i2c_start <= 1'b0;
                    if (i2c_ready) begin
                        if (reg_index < NUM_REGS - 1) begin
                            reg_index <= reg_index + 1'd1;
                            state     <= DELAY;
                            delay_cnt <= 20'd10000;
                        end else begin
                            config_done <= 1'b1;
                            state       <= IDLE;
                        end
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

// ===== END wm8731_config.v =====


// ===== BEGIN wm8731_i2c_controller.v =====

`timescale 1ns/1ps
module i2c_controller (
    input             clk,
    input             reset,
    input             start,
    input      [6:0]  device_addr,
    input      [15:0] register_data,
    output reg        ready,
    output reg        i2c_sclk,
    inout             i2c_sdat
);
    localparam DIVIDER    = 250;
    localparam IDLE       = 4'd0;
    localparam START_COND = 4'd1;
    localparam ADDR_BYTE  = 4'd2;
    localparam ACK1       = 4'd3;
    localparam DATA_HIGH  = 4'd4;
    localparam ACK2       = 4'd5;
    localparam DATA_LOW   = 4'd6;
    localparam ACK3       = 4'd7;
    localparam STOP_COND  = 4'd8;
    localparam DONE       = 4'd9;

    reg [3:0]  state;
    reg [8:0]  clk_div;
    reg [3:0]  bit_cnt;
    reg [7:0]  addr_byte;
    reg [7:0]  data_high_byte;
    reg [7:0]  data_low_byte;
    reg        sdat_out;
    reg        sdat_oe;

    assign i2c_sdat = sdat_oe ? sdat_out : 1'bz;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state      <= IDLE;
            ready      <= 1'b1;
            i2c_sclk   <= 1'b1;
            sdat_out   <= 1'b1;
            sdat_oe    <= 1'b1;
            clk_div    <= 9'd0;
            bit_cnt    <= 4'd0;
        end else begin
            clk_div <= clk_div + 1'd1;
            if (clk_div == DIVIDER) begin
                clk_div <= 9'd0;
                case (state)
                    IDLE: begin
                        ready    <= 1'b1;
                        i2c_sclk <= 1'b1;
                        sdat_out <= 1'b1;
                        sdat_oe  <= 1'b1;
                        if (start) begin
                            ready          <= 1'b0;
                            addr_byte      <= {device_addr, 1'b0};
                            data_high_byte <= register_data[15:8];
                            data_low_byte  <= register_data[7:0];
                            state          <= START_COND;
                        end
                    end
                    START_COND: begin
                        sdat_out <= 1'b0;
                        state    <= ADDR_BYTE;
                        bit_cnt  <= 4'd7;
                    end
                    ADDR_BYTE: begin
                        i2c_sclk <= 1'b0;
                        sdat_out <= addr_byte[bit_cnt];
                        if (bit_cnt == 0) state <= ACK1;
                        else begin
                            bit_cnt  <= bit_cnt - 1'd1;
                            i2c_sclk <= 1'b1;
                        end
                    end
                    ACK1: begin
                        i2c_sclk <= 1'b0;
                        sdat_oe  <= 1'b0;
                        i2c_sclk <= 1'b1;
                        state    <= DATA_HIGH;
                        bit_cnt  <= 4'd7;
                    end
                    DATA_HIGH: begin
                        i2c_sclk <= 1'b0;
                        sdat_oe  <= 1'b1;
                        sdat_out <= data_high_byte[bit_cnt];
                        if (bit_cnt == 0) state <= ACK2;
                        else begin
                            bit_cnt  <= bit_cnt - 1'd1;
                            i2c_sclk <= 1'b1;
                        end
                    end
                    ACK2: begin
                        i2c_sclk <= 1'b0;
                        sdat_oe  <= 1'b0;
                        i2c_sclk <= 1'b1;
                        state    <= DATA_LOW;
                        bit_cnt  <= 4'd7;
                    end
                    DATA_LOW: begin
                        i2c_sclk <= 1'b0;
                        sdat_oe  <= 1'b1;
                        sdat_out <= data_low_byte[bit_cnt];
                        if (bit_cnt == 0) state <= ACK3;
                        else begin
                            bit_cnt  <= bit_cnt - 1'd1;
                            i2c_sclk <= 1'b1;
                        end
                    end
                    ACK3: begin
                        i2c_sclk <= 1'b0;
                        sdat_oe  <= 1'b0;
                        i2c_sclk <= 1'b1;
                        state    <= STOP_COND;
                    end
                    STOP_COND: begin
                        i2c_sclk <= 1'b0;
                        sdat_oe  <= 1'b1;
                        sdat_out <= 1'b0;
                        i2c_sclk <= 1'b1;
                        sdat_out <= 1'b1;
                        state    <= DONE;
                    end
                    DONE: begin
                        ready <= 1'b1;
                        state <= IDLE;
                    end
                    default: state <= IDLE;
                endcase
            end
        end
    end
endmodule

// ===== END wm8731_i2c_controller.v =====


// ===== BEGIN wm8731_i2s_interface.v =====

`timescale 1ns/1ps
module i2s_interface (
    input             clk,
    input             reset,
    input             aud_adclrck,
    input             aud_bclk,
    input             aud_adcdat,
    output reg        aud_dacdat,
    input      [15:0] audio_out_l,
    input      [15:0] audio_out_r,
    output reg [15:0] audio_in_l,
    output reg [15:0] audio_in_r,
    output reg        audio_valid
);
    reg [2:0] bclk_sync;
    reg [2:0] lrck_sync;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            bclk_sync <= 3'b000;
            lrck_sync <= 3'b000;
        end else begin
            bclk_sync <= {bclk_sync[1:0], aud_bclk};
            lrck_sync <= {lrck_sync[1:0], aud_adclrck};
        end
    end

    wire bclk_rising  = (bclk_sync[2:1] == 2'b01);
    wire bclk_falling = (bclk_sync[2:1] == 2'b10);
    wire lrck_edge    = (lrck_sync[2:1] != 2'b00) && (lrck_sync[2:1] != 2'b11);
    wire left_channel = ~lrck_sync[2];

    reg [15:0] adc_shift_reg;
    reg [15:0] dac_shift_reg;
    reg [4:0]  bit_cnt;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            adc_shift_reg <= 16'd0;
            dac_shift_reg <= 16'd0;
            bit_cnt       <= 5'd0;
            audio_in_l    <= 16'd0;
            audio_in_r    <= 16'd0;
            aud_dacdat    <= 1'b0;
            audio_valid   <= 1'b0;
        end else begin
            audio_valid <= 1'b0;

            if (lrck_edge) begin
                bit_cnt <= 5'd15;
                if (left_channel) begin
                    dac_shift_reg <= audio_out_l;
                    audio_in_r    <= adc_shift_reg;
                    audio_valid   <= 1'b1;
                end else begin
                    dac_shift_reg <= audio_out_r;
                    audio_in_l    <= adc_shift_reg;
                end
            end else if (bclk_falling && bit_cnt < 16) begin
                aud_dacdat    <= dac_shift_reg[15];
                dac_shift_reg <= {dac_shift_reg[14:0], 1'b0};
                bit_cnt       <= bit_cnt - 1'd1;
            end else if (bclk_rising && bit_cnt < 16) begin
                adc_shift_reg <= {adc_shift_reg[14:0], aud_adcdat};
            end
        end
    end
endmodule

// ===== END wm8731_i2s_interface.v =====
