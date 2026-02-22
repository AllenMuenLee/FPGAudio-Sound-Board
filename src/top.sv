        // Auto-merged from src files: 2026-02-21 17:48:24

        // ===== BEGIN audioprocessor_top.sv =====

        // ============================================================================
        // DE1-SoC Top-Level Wrapper for Audio Processor
        // ============================================================================
        // Integrates the custom audio_processor with WM8731 codec drivers
        // Connects to DE1-SoC hardware pins for real-time audio processing
        // Controls: KEY[0]=Reset, SW[2:0]=Effect selection
        // Status: VU meter displays audio level on LEDR[9:0]
        // ============================================================================


        // ============================================================================
        // Audio Processor Module - Effect Selector
        // ============================================================================
        // Instantiates all effect modules from main1.sv and selects between them
        // All effects process in parallel, output mux selects based on SW[2:0]
        // ============================================================================
        `timescale 1ns/1ps
        module audio_processor (
            input             clk,
            input             reset,
            input      [15:0] audio_in,
            input      [9:0]  SW,
            output reg [15:0] audio_out
        );
            wire [2:0] effect_select;
            assign effect_select = SW[2:0];
            
            wire [15:0] noise_gate_out;
            wire [15:0] high_pitch_out;
            wire [15:0] low_pitch_out;
            wire [15:0] reverb_out;
            wire [15:0] muffled_out;

            // Shared RAM signals for time-multiplexed effects
            wire [13:0] hp_ram_wr_addr;
            wire [15:0] hp_ram_wr_data;
            wire        hp_ram_wr_en;
            wire [13:0] hp_ram_rd_addr;
            wire [15:0] hp_ram_rd_data;

            wire [13:0] lp_ram_wr_addr;
            wire [15:0] lp_ram_wr_data;
            wire        lp_ram_wr_en;
            wire [13:0] lp_ram_rd_addr;
            wire [15:0] lp_ram_rd_data;

            wire [13:0] rev_ram_wr_addr;
            wire [15:0] rev_ram_wr_data;
            wire        rev_ram_wr_en;
            wire [13:0] rev_ram_rd_addr;
            wire [15:0] rev_ram_rd_data;

            reg         ram_we_a;
            reg  [13:0] ram_addr_a;
            reg  [15:0] ram_din_a;
            reg  [13:0] ram_addr_rd;
            wire [7:0]  ram_dout_byte;
            reg  [7:0]  ram_rd_lo;
            reg  [7:0]  ram_rd_hi;
            reg  [15:0] ram_rd_data;
            reg         ram_phase;
            reg  [15:0] ram_din_latched;
            wire        clk_en;
            
            noise_gate ng_inst (.clk(clk), .reset(reset), .audio_in(audio_in), .audio_out(noise_gate_out));
            high_pitch_effect hp_inst (
                .clk(clk),
                .clk_en(clk_en),
                .reset(reset),
                .audio_in(audio_in),
                .audio_out(high_pitch_out),
                .ram_wr_addr(hp_ram_wr_addr),
                .ram_wr_data(hp_ram_wr_data),
                .ram_wr_en(hp_ram_wr_en),
                .ram_rd_addr(hp_ram_rd_addr),
                .ram_rd_data(hp_ram_rd_data)
            );
            low_pitch_effect lp_inst (
                .clk(clk),
                .clk_en(clk_en),
                .reset(reset),
                .audio_in(audio_in),
                .audio_out(low_pitch_out),
                .ram_wr_addr(lp_ram_wr_addr),
                .ram_wr_data(lp_ram_wr_data),
                .ram_wr_en(lp_ram_wr_en),
                .ram_rd_addr(lp_ram_rd_addr),
                .ram_rd_data(lp_ram_rd_data)
            );
            reverb_effect rev_inst (
                .clk(clk),
                .clk_en(clk_en),
                .reset(reset),
                .audio_in(audio_in),
                .audio_out(reverb_out),
                .ram_wr_addr(rev_ram_wr_addr),
                .ram_wr_data(rev_ram_wr_data),
                .ram_wr_en(rev_ram_wr_en),
                .ram_rd_addr(rev_ram_rd_addr),
                .ram_rd_data(rev_ram_rd_data)
            );
            muffled_effect muf_inst (.clk(clk), .reset(reset), .audio_in(audio_in), .audio_out(muffled_out));

            // Shared RAM: only the selected effect drives the memory each cycle
            always @* begin
                ram_we_a = 1'b0;
                ram_addr_a = 14'd0;
                ram_din_a = 16'd0;
                ram_addr_rd = 14'd0;
                case (effect_select)
                    3'b001: begin // High pitch
                        ram_we_a = hp_ram_wr_en;
                        ram_addr_a = hp_ram_wr_addr;
                        ram_din_a = hp_ram_wr_data;
                        ram_addr_rd = hp_ram_rd_addr;
                    end
                    3'b010: begin // Low pitch
                        ram_we_a = lp_ram_wr_en;
                        ram_addr_a = lp_ram_wr_addr;
                        ram_din_a = lp_ram_wr_data;
                        ram_addr_rd = lp_ram_rd_addr;
                    end
                    3'b011: begin // Reverb (single-port usage)
                        ram_we_a = rev_ram_wr_en;
                        ram_addr_a = rev_ram_wr_addr;
                        ram_din_a = rev_ram_wr_data;
                        ram_addr_rd = rev_ram_rd_addr;
                    end
                    default: begin
                        ram_we_a = 1'b0;
                        ram_addr_a = 14'd0;
                        ram_din_a = 16'd0;
                        ram_addr_rd = 14'd0;
                    end
                endcase
            end

            // Two-phase byte RAM access: low byte on phase 0, high byte on phase 1
            assign clk_en = ram_phase;

            shared_byte_ram_8x15 shared_ram (
                .clk(clk),
                .we(ram_we_a),
                .addr_wr({ram_addr_a, ram_phase}),
                .din((ram_phase == 1'b0) ? ram_din_a[7:0] : ram_din_latched[15:8]),
                .addr_rd({ram_addr_rd, ram_phase}),
                .dout(ram_dout_byte)
            );

            always @(posedge clk or posedge reset) begin
                if (reset) begin
                    ram_phase <= 1'b0;
                    ram_din_latched <= 16'd0;
                    ram_rd_lo <= 8'd0;
                    ram_rd_hi <= 8'd0;
                    ram_rd_data <= 16'd0;
                end else begin
                    if (ram_phase == 1'b0) begin
                        ram_din_latched <= ram_din_a;
                        ram_rd_lo <= ram_dout_byte;
                    end else begin
                        ram_rd_hi <= ram_dout_byte;
                        ram_rd_data <= {ram_dout_byte, ram_rd_lo};
                    end
                    ram_phase <= ~ram_phase;
                end
            end

            assign hp_ram_rd_data = (effect_select == 3'b001) ? ram_rd_data : 16'd0;
            assign lp_ram_rd_data = (effect_select == 3'b010) ? ram_rd_data : 16'd0;
            assign rev_ram_rd_data = (effect_select == 3'b011) ? ram_rd_data : 16'd0;
            
            always @(posedge clk or posedge reset) begin
                if (reset) audio_out <= 16'd0;
                else begin
                    if (ram_phase == 1'b1) begin
                        case (effect_select)
                            3'b000: audio_out <= noise_gate_out;
                            3'b001: audio_out <= high_pitch_out;
                            3'b010: audio_out <= low_pitch_out;
                            3'b011: audio_out <= reverb_out;
                            3'b100: audio_out <= muffled_out;
                            default: audio_out <= audio_in;
                        endcase
                    end
                end
            end
        endmodule

        // ============================================================================
        // Top-Level System Integration
        // ============================================================================

        module de1soc_audio_top (
            // ========================================================================
            // Clock and Reset
            // ========================================================================
            input         CLOCK_50,      // 50MHz system clock
            input  [3:0]  KEY,           // Push buttons (active low)
            
            // ========================================================================
            // User Interface
            // ========================================================================
            input  [9:0]  SW,            // Slide switches for effect selection
            output [9:0]  LEDR,          // Red LEDs for status display
            
            // ========================================================================
            // Audio Codec (WM8731) Interface Pins
            // ========================================================================
            input         AUD_ADCDAT,    // ADC serial data from codec
            input         AUD_ADCLRCK,   // ADC left/right clock from codec
            input         AUD_BCLK,      // Bit clock from codec
            output        AUD_DACDAT,    // DAC serial data to codec
            input         AUD_DACLRCK,   // DAC left/right clock from codec
            output        AUD_XCK,       // Master clock to codec
            
            // ========================================================================
            // I2C Configuration Interface
            // ========================================================================
            output        FPGA_I2C_SCLK, // I2C clock for codec configuration
            inout         FPGA_I2C_SDAT  // I2C data for codec configuration
        );

            // ========================================================================
            // Reset Logic
            // ========================================================================
            // Convert active-low KEY[0] button to active-high reset signal
            wire reset;
            assign reset = ~KEY[0];
            
            // ========================================================================
            // Audio Clock Generation
            // ========================================================================
            // Generate ~12.5MHz master clock for WM8731 codec
            // Required for 48kHz sample rate operation
            audio_clock clk_gen (
                .clk_50mhz(CLOCK_50),
                .reset(reset),
                .aud_xck(AUD_XCK)
            );
            
            // ========================================================================
            // WM8731 Configuration via I2C
            // ========================================================================
            // Initialize codec registers at startup
            // Configures: Master mode, 48kHz, Line In/Out enabled
            wire config_done;
            
            wm8731_config codec_config (
                .clk(CLOCK_50),
                .reset(reset),
                .config_done(config_done),
                .i2c_sclk(FPGA_I2C_SCLK),
                .i2c_sdat(FPGA_I2C_SDAT)
            );
            
            // ========================================================================
            // I2S Audio Interface
            // ========================================================================
            // Handles serial audio data streaming with WM8731
            // Converts I2S serial data to/from parallel 16-bit samples
            wire [15:0] audio_in_left;     // Left channel from ADC
            wire [15:0] audio_in_right;    // Right channel from ADC
            wire [15:0] audio_out_left;    // Left channel to DAC
            wire [15:0] audio_out_right;   // Right channel to DAC
            wire        audio_valid;       // New sample ready flag
            
            i2s_interface i2s (
                .clk(CLOCK_50),
                .reset(reset),
                // I2S codec connections
                .aud_adclrck(AUD_ADCLRCK),
                .aud_bclk(AUD_BCLK),
                .aud_adcdat(AUD_ADCDAT),
                .aud_dacdat(AUD_DACDAT),
                // Parallel audio data
                .audio_out_l(audio_out_left),
                .audio_out_r(audio_out_right),
                .audio_in_l(audio_in_left),
                .audio_in_r(audio_in_right),
                .audio_valid(audio_valid)
            );
            
            // ========================================================================
            // Custom Audio Processor - Left Channel
            // ========================================================================
            // Process left channel audio with selected effect
            // Effect selection via SW[2:0]:
            //   000 = Noise Gate
            //   001 = High Pitch
            //   010 = Low Pitch
            //   011 = Reverb
            //   100 = Muffled
            audio_processor dsp_left (
                .clk(CLOCK_50),
                .reset(reset),
                .audio_in(audio_in_left),
                .SW(SW),
                .audio_out(audio_out_left)
            );
            
            // ========================================================================
            // Custom Audio Processor - Right Channel
            // ========================================================================
            // Process right channel audio with same effect as left
            // Creates stereo output with identical processing
            audio_processor dsp_right (
                .clk(CLOCK_50),
                .reset(reset),
                .audio_in(audio_in_right),
                .SW(SW),
                .audio_out(audio_out_right)
            );
            
            // ========================================================================
            // VU Meter - Real-Time Audio Visualization
            // ========================================================================
            // Display processed audio volume level on LEDs as a bar graph
            // Features peak hold and smooth decay for flicker-free display
            // Monitors left channel processed audio output
            vu_meter audio_visualizer (
                .clk(CLOCK_50),
                .reset(reset),
                .audio_sample(audio_out_left),  // Monitor processed audio
                .led_out(LEDR)                   // Drive all 10 LEDs
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

        // ===== END de1soc_top.sv =====

        // ===== BEGIN effect_highpitch.v =====

        /*
        * Generated by Digital. Don't modify this file!
        * Any changes will be lost if this file is regenerated.
        */
        `timescale 1ns/1ps

        module high_pitch_effect (
        input wire clk,
        input wire clk_en,
        input wire reset,
        input [15:0] audio_in,
        output [15:0] audio_out,
        output [13:0] ram_wr_addr,
        output [15:0] ram_wr_data,
        output        ram_wr_en,
        output [13:0] ram_rd_addr,
        input  [15:0] ram_rd_data
        );
        wire [13:0] s0;
        wire [13:0] s1;
        wire [17:0] s2;
        wire [17:0] s3;
        wire unused_counter_ovf;
        wire unused_add_co;
        DIG_Counter_Nbit #(
            .Bits(14)
        )
        DIG_Counter_Nbit_i0 (
            .en( clk_en ),
            .C( clk ),
            .clr( reset ),
            .out( s0 ),
            .ovf( unused_counter_ovf )
        );
        assign ram_wr_en = 1'b1;
        assign ram_wr_addr = s0;
        assign ram_wr_data = audio_in[15:0];
        assign ram_rd_addr = s1;
        assign audio_out = ram_rd_data;
        DIG_Add #(
            .Bits(18)
        )
        DIG_Add_i2 (
            .a( s2 ),
            .b( 18'b100000 ),
            .c_i( 1'b0 ),
            .s( s3 ),
            .c_o( unused_add_co )
        );
        DIG_Register_BUS #(
            .Bits(18)
        )
        DIG_Register_BUS_i3 (
            .D( s3 ),
            .C( clk ),
            .en( clk_en ),
            .Q( s2 )
        );
        assign s1 = s2[17:4];
        endmodule

        // ===== END effect_highpitch.v =====

        // ===== BEGIN effect_lowpitch.v =====

        /*
        * Generated by Digital. Don't modify this file!
        * Any changes will be lost if this file is regenerated.
        */
        `timescale 1ns/1ps

        module low_pitch_effect (
        input wire clk,
        input wire clk_en,
        input wire reset,
        input [15:0] audio_in,
        output [15:0] audio_out,
        output [13:0] ram_wr_addr,
        output [15:0] ram_wr_data,
        output        ram_wr_en,
        output [13:0] ram_rd_addr,
        input  [15:0] ram_rd_data
        );
        wire [13:0] s0;
        wire [13:0] s1;
        wire [17:0] s2;
        wire [17:0] s3;
        wire unused_counter_ovf;
        wire unused_add_co;
        DIG_Counter_Nbit #(
            .Bits(14)
        )
        DIG_Counter_Nbit_i0 (
            .en( clk_en ),
            .C( clk ),
            .clr( 1'b0 ),
            .out( s0 ),
            .ovf( unused_counter_ovf )
        );
        assign ram_wr_en = 1'b1;
        assign ram_wr_addr = s0;
        assign ram_wr_data = audio_in[15:0];
        assign ram_rd_addr = s1;
        assign audio_out = ram_rd_data;
        DIG_Add #(
            .Bits(18)
        )
        DIG_Add_i2 (
            .a( s2 ),
            .b( 18'b1000 ),
            .c_i( 1'b0 ),
            .s( s3 ),
            .c_o( unused_add_co )
        );
        DIG_Register_BUS #(
            .Bits(18)
        )
        DIG_Register_BUS_i3 (
            .D( s3 ),
            .C( clk ),
            .en( clk_en ),
            .Q( s2 )
        );
        assign s1 = s2[17:4];
        endmodule


        // ===== END effect_lowpitch.v =====

        // ===== BEGIN effect_muffled.v =====

        /*
        * Generated by Digital. Don't modify this file!
        * Any changes will be lost if this file is regenerated.
        */
        `timescale 1ns/1ps

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
        wire unused_sub0_co;
        wire unused_sub1_co;
        wire unused_add0_co;
        wire unused_add1_co;
        wire unused_add2_co;
        // Sub_1
        DIG_Sub #(
            .Bits(16)
        )
        DIG_Sub_i0 (
            .a( audio_in[15:0] ),
            .b( y_1[15:0] ),
            .c_i( 1'b0 ),
            .s( s0 ),
            .c_o( unused_sub0_co )
        );
        assign s7 = s0[15];
        assign s2[11:0] = s0[15:4];
        assign s2[12] = s7;
        assign s2[13] = s7;
        assign s2[14] = s7;
        assign s2[15] = s7;
        // Add_1
        DIG_Add #(
            .Bits(16)
        )
        DIG_Add_i1 (
            .a( s2[15:0] ),
            .b( y_1[15:0] ),
            .c_i( 1'b0 ),
            .s( s3 ),
            .c_o( unused_add0_co )
        );
        // Reg_1
        DIG_Register_BUS #(
            .Bits(16)
        )
        DIG_Register_BUS_i2 (
            .D( s3 ),
            .C( clk ),
            .en( 1'b1 ),
            .Q( y_1 )
        );
        // Sub_2
        DIG_Sub #(
            .Bits(16)
        )
        DIG_Sub_i3 (
            .a( y_1[15:0] ),
            .b( y_2[15:0] ),
            .c_i( 1'b0 ),
            .s( s1 ),
            .c_o( unused_sub1_co )
        );
        assign s8 = s1[15];
        assign s4[11:0] = s1[15:4];
        assign s4[12] = s8;
        assign s4[13] = s8;
        assign s4[14] = s8;
        assign s4[15] = s8;
        // Add_2
        DIG_Add #(
            .Bits(16)
        )
        DIG_Add_i4 (
            .a( s4[15:0] ),
            .b( y_2[15:0] ),
            .c_i( 1'b0 ),
            .s( s5 ),
            .c_o( unused_add1_co )
        );
        // Reg_2
        DIG_Register_BUS #(
            .Bits(16)
        )
        DIG_Register_BUS_i5 (
            .D( s5 ),
            .C( clk ),
            .en( 1'b1 ),
            .Q( y_2 )
        );
        assign s9 = y_2[15];
        assign s6[11:0] = y_2[15:4];
        assign s6[12] = s9;
        assign s6[13] = s9;
        assign s6[14] = s9;
        assign s6[15] = s9;
        // Add_3
        DIG_Add #(
            .Bits(16)
        )
        DIG_Add_i6 (
            .a( s6[15:0] ),
            .b( y_2[15:0] ),
            .c_i( 1'b0 ),
            .s( audio_out ),
            .c_o( unused_add2_co )
        );
        endmodule

        // ===== END effect_muffled.v =====

        // ===== BEGIN effect_noisegate.v =====

        // ============================================================================
        // Noise Gate Effect Module - Corrected Version
        // ============================================================================
        // Generated by Digital simulator, modified for proper port naming
        //
        // IMPORTANT: This file requires digital_utils.v with shared utility modules
        //
        // Implements adaptive noise gate with attack/release thresholds
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
        // Unused outputs from utility modules
        wire unused_comp_eq0, unused_comp_lt0, unused_comp_gt1, unused_comp_eq1;
        wire unused_comp_eq2, unused_comp_lt2, unused_comp_gt3, unused_comp_eq3;
        wire unused_add_co;
        
        DIG_Neg #(
            .Bits(16)
        )
        DIG_Neg_i0 (
            .in( audio_in ),
            .out( s1 )
        );
        assign s0 = audio_in[15];
        Mux_2x1_NBits #(
            .Bits(16)
        )
        Mux_2x1_NBits_i1 (
            .sel( s0 ),
            .in_0( audio_in ),
            .in_1( s1 ),
            .out( s2 )
        );
        // Attack
        CompUnsigned #(
            .Bits(16)
        )
        CompUnsigned_i2 (
            .a( s2 ),
            .b( 16'b1111101000 ),
            .\> ( s3 ),
            .\= ( unused_comp_eq0 ),
            .\< ( unused_comp_lt0 )
        );
        // Release
        CompUnsigned #(
            .Bits(16)
        )
        CompUnsigned_i3 (
            .a( s2 ),
            .b( 16'b111110100 ),
            .\> ( unused_comp_gt1 ),
            .\= ( unused_comp_eq1 ),
            .\< ( s4 )
        );
        // volume
        DIG_Mul_unsigned #(
            .Bits(16)
        )
        DIG_Mul_unsigned_i4 (
            .a( s10 ),
            .b( s2 ),
            .mul( s11 )
        );
        // Gate state machine with proper sequential logic
        always @(posedge clk or posedge reset) begin
            if (reset) begin
            s7 <= 1'b0;
            end else begin
            if (s3) begin
                s7 <= 1'b1;
            end else if (s4) begin
                s7 <= 1'b0;
            end
            end
        end
        Mux_2x1_NBits #(
            .Bits(11)
        )
        Mux_2x1_NBits_i5 (
            .sel( s7 ),
            .in_0( 11'b1010 ),
            .in_1( 11'b11111110110 ),
            .out( s8 )
        );
        assign audio_out = s11[25:10];
        // step adder
        DIG_Add #(
            .Bits(11)
        )
        DIG_Add_i6 (
            .a( s6 ),
            .b( s8 ),
            .c_i( 1'b0 ),
            .s( s9 ),
            .c_o( unused_add_co )
        );
        // extender
        DIG_BitExtender #(
            .inputBits(11),
            .outputBits(16)
        )
        DIG_BitExtender_i7 (
            .in( s9 ),
            .out( s10 )
        );
        // check gain max
        CompUnsigned #(
            .Bits(11)
        )
        CompUnsigned_i8 (
            .a( 11'b10000000000 ),
            .b( s9 ),
            .\> ( s12 ),
            .\= ( unused_comp_eq2 ),
            .\< ( unused_comp_lt2 )
        );
        Mux_2x1_NBits #(
            .Bits(11)
        )
        Mux_2x1_NBits_i9 (
            .sel( s12 ),
            .in_0( 11'b10000000000 ),
            .in_1( s9 ),
            .out( s13 )
        );
        // check gain min
        CompUnsigned #(
            .Bits(11)
        )
        CompUnsigned_i10 (
            .a( 11'b1100110 ),
            .b( s13 ),
            .\> ( unused_comp_gt3 ),
            .\= ( unused_comp_eq3 ),
            .\< ( s14 )
        );
        Mux_2x1_NBits #(
            .Bits(11)
        )
        Mux_2x1_NBits_i11 (
            .sel( s14 ),
            .in_0( 11'b1100110 ),
            .in_1( s13 ),
            .out( s5 )
        );
        // gain
        DIG_Register_BUS #(
            .Bits(11)
        )
        DIG_Register_BUS_i12 (
            .D( s5 ),
            .C( clk ),
            .en( 1'b1 ),
            .Q( s6 )
        );
        endmodule

        // ===== END effect_noisegate.v =====

        // ===== BEGIN effect_none.sv =====


        // ===== END effect_none.sv =====

        // ===== BEGIN effect_reverb.v =====

        /*
        * Generated by Digital. Don't modify this file!
        * Any changes will be lost if this file is regenerated.
        */
        `timescale 1ns/1ps

        module reverb_effect (
        input wire clk,
        input wire clk_en,
        input wire reset,   
        input [15:0] audio_in, // Audio input (not too loud or else)
        output [15:0] audio_out, // evertime sound loops it becomes 25% vol
        output [13:0] ram_wr_addr,
        output [15:0] ram_wr_data,
        output        ram_wr_en,
        output [13:0] ram_rd_addr,
        input  [15:0] ram_rd_data

        );
        wire [13:0] s0;
        wire [15:0] s1;
        wire [15:0] s2;
        wire [15:0] s3;
        wire s4;
        wire unused_counter_ovf;
        wire unused_add0_co;
        wire unused_add1_co;
        DIG_Counter_Nbit #(
            .Bits(14)
        )
        DIG_Counter_Nbit_i0 (
            .en( clk_en ),
            .C( clk ),
            .clr( 1'b0 ),
            .out( s0 ),
            .ovf( unused_counter_ovf )
        );
        assign ram_wr_en = 1'b1;
        assign ram_wr_addr = s0;
        assign ram_wr_data = s1;
        assign ram_rd_addr = s0;
        assign s2 = ram_rd_data;
        // feedbmix
        DIG_Add #(
            .Bits(16)
        )
        DIG_Add_i2 (
            .a( audio_in[15:0] ),
            .b( s3[15:0] ),
            .c_i( 1'b0 ),
            .s( s1 ),
            .c_o( unused_add0_co )
        );
        // outputmix
        DIG_Add #(
            .Bits(16)
        )
        DIG_Add_i3 (
            .a( audio_in[15:0] ),
            .b( s2[15:0] ),
            .c_i( 1'b0 ),
            .s( audio_out ),
            .c_o( unused_add1_co )
        );
        assign s4 = s2[15];
        assign s3[11:0] = s2[15:4];
        assign s3[12] = s4;
        assign s3[13] = s4;
        assign s3[14] = s4;
        assign s3[15] = s4;
        endmodule

        // ===== END effect_reverb.v =====

        // ===== BEGIN util_audioclock.v =====

        // ============================================================================
        // Audio Clock Generator for WM8731
        // ============================================================================
        // Generates AUD_XCK (master clock) for the WM8731 codec
        // Target: 12.288 MHz for 48kHz operation (48kHz * 256)
        // From 50MHz: Divide by ~4.07 ≈ 12.285 MHz (very close!)
        // ============================================================================
        `timescale 1ns/1ps
        module audio_clock (
            input      clk_50mhz,    // 50MHz input clock
            input      reset,        // Active high reset
            output reg aud_xck       // Audio master clock output (~12.288MHz)
        );

            // Clock divider for generating ~12.288MHz from 50MHz
            // 50MHz / 4.069 ≈ 12.288MHz
            // Use fractional divider: toggle every 2 or 2 cycles alternating
            
            reg [2:0] counter;
            reg [1:0] pattern_idx;
            
            // Pattern: 2, 2, 2, 2 cycles = divide by 4 (12.5MHz)
            // Better: Use PLL in real design, but for simplicity use approximation
            // Divide by 4 gives 12.5MHz (close enough for WM8731)
            
            always @(posedge clk_50mhz or posedge reset) begin
                if (reset) begin
                    counter <= 3'd0;
                    aud_xck <= 1'b0;
                end else begin
                    if (counter >= 3'd1) begin  // Divide by 4 (toggle every 2 clocks)
                        counter <= 3'd0;
                        aud_xck <= ~aud_xck;
                    end else begin
                        counter <= counter + 1'd1;
                    end
                end
            end

        endmodule

        // ===== END util_audioclock.v =====

        // ===== BEGIN util_digital.v =====

        // ============================================================================
        // Digital Simulator Utility Modules - Shared Components
        // ============================================================================
        // Common building blocks generated by Digital simulator tool
        // Used by multiple audio effect modules (high pitch, low pitch, reverb, etc.)
        // Include this file once to avoid duplicate module declarations
        // ============================================================================

        // MODULE LIST
        // DIG_Counter_Nbit - Up counter with clear
        // DIG_RAMDualAccess - Two-port RAM (write on port 1, independent read on port 2)
        // DIG_RAMDualPort - Single-port RAM (unified address for read/write)
        // DIG_Add - Full adder with carry
        // DIG_Sub - Full subtractor with borrow
        // DIG_Register_BUS - Enabled register
        // DIG_Neg - Two's complement negation (for absolute value calculation)
        // Mux_2x1_NBits - 2-to-1 multiplexer (for conditional data routing)
        // CompUnsigned - Unsigned comparator with >, =, < outputs (for threshold detection)
        // DIG_Mul_unsigned - Unsigned multiplier (for gain/volume control)
        // DIG_BitExtender - Sign/zero extension (for width matching)

        // ============================================================================
        // N-Bit Counter Module
        // ============================================================================
        // Parametrizable up-counter with enable and synchronous clear
        // Used for address generation and timing control
        // ============================================================================
        module DIG_Counter_Nbit
        #(
            parameter Bits = 2  // Counter width in bits
        )
        (
            output [(Bits-1):0] out,  // Current count value
            output ovf,                // Overflow flag (all bits high)
            input C,                   // Clock signal
            input en,                  // Enable: counter increments when high
            input clr                  // Clear: synchronously resets counter to 0
        );
            reg [(Bits-1):0] count;
            
            // Synchronous counter logic
            always @ (posedge C) begin
                if (clr)
                count <= 'h0;              // Reset to zero
                else if (en)
                count <= count + 1'b1;     // Increment by 1
            end
            
            assign out = count;
            assign ovf = en? &count : 1'b0;  // Overflow when all bits are 1
            
            initial begin
                count = 'h0;  // Initialize to zero
            end
        endmodule

        // ============================================================================
        // Dual-Port RAM Module (Two Independent Ports)
        // ============================================================================
        // True dual-port memory with independent read/write operations
        // Port 1: Read/Write with separate addresses
        // Port 2: Independent read with separate address
        // Memory Type: Distributed RAM (implemented in FPGA LUTs, not block RAM)
        // ============================================================================
        module DIG_RAMDualAccess
        #(
            parameter Bits = 8,       // Data width in bits
            parameter AddrBits = 4    // Address width (memory size = 2^AddrBits)
        )
        (
            input C,                           // Clock signal
            input ld,                          // Port 1 load enable (read enable)
            input [(AddrBits-1):0] \1A ,       // Port 1 address (write address)
            input [(AddrBits-1):0] \2A ,       // Port 2 address (read address)
            input [(Bits-1):0] \1Din ,         // Port 1 data input (write data)
            input str,                         // Port 1 store enable (write enable)
            output [(Bits-1):0] \1D ,          // Port 1 data output (read data)
            output [(Bits-1):0] \2D            // Port 2 data output (read data)
        );
            // Memory array: Depth = 2^AddrBits words
            reg [(Bits-1):0] memory [0:((1 << AddrBits)-1)];
            
            // Port 1: Tri-state output when not reading
            assign \1D = ld? memory[\1A ] : {Bits{1'b0}};
            
            // Port 2: Always reads current address
            assign \2D = memory[\2A ];
            
            // Synchronous write on Port 1
            always @ (posedge C) begin
                if (str)
                    memory[\1A ] <= \1Din ;  // Write data to memory
            end

        endmodule

        // ============================================================================
        // Single-Port RAM Module
        // ============================================================================
        // Simple RAM with single address port for both read and write
        // Used for delay lines and simple memory buffers
        // Memory Type: Distributed RAM (implemented in FPGA LUTs, not block RAM)
        // ============================================================================
        module DIG_RAMDualPort
        #(
            parameter Bits = 16,      // Data width in bits
            parameter AddrBits = 4    // Address width (memory size = 2^AddrBits)
        )
        (
            input [(AddrBits-1):0] A,     // Address for read/write
            input [(Bits-1):0] Din,       // Data input (write data)
            input str,                    // Store enable (write enable)
            input C,                      // Clock signal
            input ld,                     // Load enable (read enable)
            output [(Bits-1):0] D         // Data output (read data)
        );
            reg [(Bits-1):0] memory[0:((1 << AddrBits) - 1)];
            
            // Read operation (conditional based on ld)
            assign D = ld? memory[A] : {Bits{1'b0}};
            
            // Synchronous write operation
            always @ (posedge C) begin
                if (str)
                    memory[A] <= Din;
            end
        endmodule

        // ============================================================================
        // Shared RAM Module (Single Instance for All Effects)
        // ============================================================================
        // One write port (A) with readback, plus a second read port (B).
        // Used by time-multiplexed effects to reduce total RAM usage.
        // ============================================================================
        module shared_byte_ram_8x15 (
            input         clk,
            input         we,
            input  [14:0] addr_wr,
            input  [7:0]  din,
            input  [14:0] addr_rd,
            output reg [7:0]  dout
        );
            reg [7:0] memory [0:32767];

            // Synchronous read and write
            always @ (posedge clk) begin
                dout <= memory[addr_rd];
                if (we)
                    memory[addr_wr] <= din;
            end
        endmodule

        // ============================================================================
        // N-Bit Adder Module
        // ============================================================================
        // Full adder with carry-in and carry-out
        // Used for pointer arithmetic and accumulation
        // ============================================================================
        module DIG_Add
        #(
            parameter Bits = 1  // Operand width in bits
        )
        (
            input [(Bits-1):0] a,        // First operand
            input [(Bits-1):0] b,        // Second operand
            input c_i,                   // Carry input
            output [(Bits - 1):0] s,     // Sum output (lower bits)
            output c_o                   // Carry output (overflow bit)
        );
        wire [Bits:0] temp;  // Extra bit for carry
        
        // Perform addition with carry
        assign temp = a + b + {{Bits{1'b0}}, c_i};
        assign s = temp [(Bits-1):0];  // Extract sum
        assign c_o = temp[Bits];       // Extract carry-out
        endmodule

        // ============================================================================
        // N-Bit Subtractor Module
        // ============================================================================
        // Full subtractor with borrow-in and borrow-out
        // Used for difference calculations in filtering operations
        // ============================================================================
        module DIG_Sub
        #(
            parameter Bits = 1  // Operand width in bits
        )
        (
            input [(Bits-1):0] a,        // Minuend (first operand)
            input [(Bits-1):0] b,        // Subtrahend (second operand)
            input c_i,                   // Borrow input
            output [(Bits-1):0] s,       // Difference output
            output c_o                   // Borrow output
        );
            wire [Bits:0] temp;  // Extra bit for borrow
            
            // Perform subtraction with borrow
            assign temp = a - b - {{Bits{1'b0}}, c_i};
            assign s = temp[(Bits-1):0];  // Extract difference
            assign c_o = temp[Bits];      // Extract borrow-out
        endmodule

        // ============================================================================
        // N-Bit Register Module
        // ============================================================================
        // Parametrizable register with enable signal
        // Used for state storage and pipeline stages
        // ============================================================================
        module DIG_Register_BUS #(
            parameter Bits = 1  // Register width in bits
        )
        (
            input C,                      // Clock signal
            input en,                     // Enable: loads D when high
            input [(Bits - 1):0]D,        // Data input
            output [(Bits - 1):0]Q        // Data output (current state)
        );

            reg [(Bits - 1):0] state = 'h0;  // Internal state storage
            
            assign Q = state;  // Output current state
            
            // Synchronous load when enabled
            always @ (posedge C) begin
                if (en)
                    state <= D;  // Load new value
        end
        endmodule

        // ============================================================================
        // N-Bit Negation Module
        // ============================================================================
        // Two's complement negation
        // Used for absolute value calculations in noise gate
        // ============================================================================
        module DIG_Neg #(
            parameter Bits = 1  // Operand width in bits
        )
        (
            input signed [(Bits-1):0] in,   // Input value
            output signed [(Bits-1):0] out  // Negated output (-in)
        );
            assign out = -in;  // Two's complement negation
        endmodule

        // ============================================================================
        // 2-to-1 Multiplexer Module
        // ============================================================================
        // Selects between two N-bit inputs based on selector
        // Used for conditional data routing
        // ============================================================================
        module Mux_2x1_NBits #(
            parameter Bits = 2  // Data width in bits
        )
        (
            input [0:0] sel,                 // Selector: 0=in_0, 1=in_1
            input [(Bits - 1):0] in_0,       // Input 0
            input [(Bits - 1):0] in_1,       // Input 1
            output reg [(Bits - 1):0] out    // Selected output
        );
            always @ (*) begin
                case (sel)
                    1'h0: out = in_0;
                    1'h1: out = in_1;
                    default: out = 'h0;
                endcase
            end
        endmodule

        // ============================================================================
        // Unsigned Comparator Module
        // ============================================================================
        // Compares two unsigned values
        // Used for threshold detection in noise gate
        // ============================================================================
        module CompUnsigned #(
            parameter Bits = 1  // Operand width in bits
        )
        (
            input [(Bits -1):0] a,  // First operand
            input [(Bits -1):0] b,  // Second operand
            output \> ,             // a > b
            output \= ,             // a == b
            output \<               // a < b
        );
            assign \> = a > b;
            assign \= = a == b;
            assign \< = a < b;
        endmodule

        // ============================================================================
        // Unsigned Multiplier Module
        // ============================================================================
        // Multiplies two unsigned N-bit values, produces 2N-bit result
        // Used for gain/volume control in noise gate
        // ============================================================================
        module DIG_Mul_unsigned #(
            parameter Bits = 1  // Input operand width
        )
        (
            input [(Bits-1):0] a,          // First operand
            input [(Bits-1):0] b,          // Second operand
            output [(Bits*2-1):0] mul      // Product (double width)
        );
            assign mul = a * b;  // Unsigned multiplication
        endmodule

        // ============================================================================
        // Bit Extension Module
        // ============================================================================
        // Sign-extends or zero-extends input to wider output
        // Used for width matching in arithmetic operations
        // ============================================================================
        module DIG_BitExtender #(
            parameter inputBits = 2,   // Input width
            parameter outputBits = 4   // Output width (must be >= inputBits)
        )
        (
            input [(inputBits-1):0] in,       // Input value
            output [(outputBits - 1):0] out   // Extended output
        );
            // Sign extension: replicate MSB for signed values
            assign out = {{(outputBits - inputBits){in[inputBits - 1]}}, in};
        endmodule

        // ===== END util_digital.v =====

        // ===== BEGIN util_vumeter.v =====

        // ============================================================================
        // VU Meter - Real-Time Audio Volume Visualizer
        // ============================================================================
        // Displays audio volume level as a bar graph on 10 LEDs
        // Features peak hold and smooth decay for flicker-free visualization
        // Monitors 16-bit signed audio samples and converts to LED output
        // ============================================================================
        `timescale 1ns/1ps
        module vu_meter (
            input             clk,           // System clock (50MHz)
            input             reset,         // Active high reset
            input      [15:0] audio_sample,  // 16-bit signed audio input
            output reg [9:0]  led_out        // 10-bit LED bar graph output
        );

            // ========================================================================
            // Signal Processing: Absolute Value Calculation
            // ========================================================================
            // Convert signed audio sample to absolute value for volume measurement
            // If MSB is 1 (negative), perform two's complement: invert and add 1
            // If MSB is 0 (positive), pass through unchanged
            wire [15:0] abs_sample;
            assign abs_sample = audio_sample[15] ? (~audio_sample + 1'b1) : audio_sample;
            
            // ========================================================================
            // Level Mapping: 16-bit Audio to 4-bit LED Level
            // ========================================================================
            // Extract top 4 bits to map 16-bit range (0-65535) to LED levels (0-15)
            // Using bits [15:12] provides good sensitivity across audio dynamic range
            wire [3:0] current_level;
            assign current_level = abs_sample[15:12];
            
            // ========================================================================
            // Peak Hold Registers
            // ========================================================================
            reg [3:0]  peak_level;      // Holds the peak level detected (0-15)
            reg [23:0] decay_counter;   // Counter for decay timing (~336ms at 50MHz)
            
            // ========================================================================
            // Timing Parameters
            // ========================================================================
            // Decay time: ~336ms gives smooth, visible LED transitions
            // At 50MHz: 16,777,215 cycles ≈ 336ms
            localparam DECAY_TIME = 24'd16_777_215;
            
            // ========================================================================
            // Peak Hold and Decay Logic
            // ========================================================================
            always @(posedge clk or posedge reset) begin
                if (reset) begin
                    // Reset all peak hold logic
                    peak_level <= 4'd0;
                    decay_counter <= 24'd0;
                    led_out <= 10'd0;
                end else begin
                    // ----------------------------------------------------------------
                    // Peak Detection: Update if current level exceeds held peak
                    // ----------------------------------------------------------------
                    if (current_level > peak_level) begin
                        peak_level <= current_level;
                        decay_counter <= DECAY_TIME;  // Reset decay timer on new peak
                    end
                    
                    // ----------------------------------------------------------------
                    // Decay Timer: Count down between level decrements
                    // ----------------------------------------------------------------
                    else if (decay_counter > 0) begin
                        decay_counter <= decay_counter - 1'b1;
                    end
                    
                    // ----------------------------------------------------------------
                    // Decay Action: Decrease peak level when timer expires
                    // ----------------------------------------------------------------
                    else begin
                        if (peak_level > 0) begin
                            peak_level <= peak_level - 1'b1;  // Drop one level
                        end
                        decay_counter <= DECAY_TIME;  // Reload timer for next decay
                    end
                    
                    // ----------------------------------------------------------------
                    // LED Bar Graph Encoding (Thermometer Code)
                    // ----------------------------------------------------------------
                    // Convert 4-bit level (0-15) to 10-bit LED pattern
                    // Lower levels light fewer LEDs (e.g., level 3 = 0b0000000111)
                    // Higher levels light more LEDs progressively
                    case (peak_level)
                        4'd0:    led_out <= 10'b0000000000;  // Silent
                        4'd1:    led_out <= 10'b0000000001;  // Very quiet
                        4'd2:    led_out <= 10'b0000000011;
                        4'd3:    led_out <= 10'b0000000111;
                        4'd4:    led_out <= 10'b0000001111;  // Low volume
                        4'd5:    led_out <= 10'b0000011111;
                        4'd6:    led_out <= 10'b0000111111;  // Medium volume
                        4'd7:    led_out <= 10'b0001111111;
                        4'd8:    led_out <= 10'b0011111111;  // High volume
                        4'd9:    led_out <= 10'b0111111111;
                        default: led_out <= 10'b1111111111;  // Maximum (levels 10-15)
                    endcase
                end
            end

        endmodule

        // ===== END util_vumeter.v =====

        // ===== BEGIN wm8731_config.v =====

        // ============================================================================
        // WM8731 Audio Codec Configuration Module
        // ============================================================================
        // Initializes the Wolfson WM8731 codec via I2C
        // Configuration: Master mode, 48kHz sample rate, Line In/Out enabled
        // Sends initialization sequence to configure all codec registers
        // ============================================================================
        `timescale 1ns/1ps
        module wm8731_config (
            input      clk,          // System clock (50MHz)
            input      reset,        // Active high reset
            output reg config_done,  // Configuration complete flag
            output     i2c_sclk,     // I2C clock output
            inout      i2c_sdat      // I2C data (bidirectional)
        );

            // ========================================================================
            // WM8731 I2C Device Address
            // ========================================================================
            // 7-bit I2C address for WM8731 (CSB pin determines address)
            localparam WM8731_ADDR = 7'b0011010;  // 0x1A (CSB=0)
            
            // ========================================================================
            // Configuration Register Count
            // ========================================================================
            localparam NUM_REGS = 10;  // Number of registers to configure
            
            // ========================================================================
            // Internal Registers
            // ========================================================================
            reg [15:0] config_data [0:NUM_REGS-1];  // Configuration data array
            reg [3:0]  reg_index;                    // Current register index
            reg        i2c_start;                    // I2C start signal
            wire       i2c_ready;                    // I2C ready signal
            
            // ========================================================================
            // WM8731 Register Configuration Data
            // ========================================================================
            // Format: [15:9] = register address, [8:0] = register data
            initial begin
                // R15 (0x0F): Reset Register
                // Write 0x00 to reset all registers to default
                config_data[0] = 16'b0001111_000000000;
                
                // R0 (0x00): Left Line In
                // Enable input, 0dB gain, unmute
                config_data[1] = 16'b0000000_010010111;
                
                // R1 (0x01): Right Line In  
                // Enable input, 0dB gain, unmute
                config_data[2] = 16'b0000001_010010111;
                
                // R2 (0x02): Left Headphone Out
                // 0dB volume, enable zero-cross detect
                config_data[3] = 16'b0000010_001111001;
                
                // R3 (0x03): Right Headphone Out
                // 0dB volume, enable zero-cross detect
                config_data[4] = 16'b0000011_001111001;
                
                // R4 (0x04): Analog Audio Path Control
                // Select line input to ADC, bypass OFF, DAC selected
                config_data[5] = 16'b0000100_000010010;
                
                // R5 (0x05): Digital Audio Path Control
                // DAC enabled, no de-emphasis
                config_data[6] = 16'b0000101_000000000;
                
                // R6 (0x06): Power Down Control
                // Power up all sections (all bits = 0)
                config_data[7] = 16'b0000110_000000000;
                
                // R7 (0x07): Digital Audio Interface Format
                // I2S format, 16-bit, Master mode, no bit clock inversion
                config_data[8] = 16'b0000111_001000010;
                
                // R8 (0x08): Sampling Control
                // Normal mode, 48kHz sample rate (with 12.288MHz MCLK)
                // USB mode off, base oversampling rate
                config_data[9] = 16'b0001000_000000000;
            end
            
            // ========================================================================
            // State Machine States
            // ========================================================================
            localparam IDLE  = 2'd0;  // Idle state
            localparam WAIT  = 2'd1;  // Wait for I2C completion
            localparam SEND  = 2'd2;  // Send I2C command
            localparam DELAY = 2'd3;  // Delay between commands
            
            reg [1:0]  state;      // State machine state
            reg [19:0] delay_cnt;  // Delay counter (20 bits for long delays)
            
            // ========================================================================
            // I2C Controller Instance
            // ========================================================================
            // Handles low-level I2C communication
            i2c_controller i2c_ctrl (
                .clk(clk),
                .reset(reset),
                .start(i2c_start),
                .device_addr(WM8731_ADDR),
                .register_data(config_data[reg_index]),
                .ready(i2c_ready),
                .i2c_sclk(i2c_sclk),
                .i2c_sdat(i2c_sdat)
            );
            
            // ========================================================================
            // Configuration Sequencer State Machine
            // ========================================================================
            // Sends all configuration registers to WM8731 in sequence
            always @(posedge clk or posedge reset) begin
                if (reset) begin
                    state <= IDLE;
                    reg_index <= 4'd0;
                    i2c_start <= 1'b0;
                    config_done <= 1'b0;
                    delay_cnt <= 20'd0;
                end else begin
                    case (state)
                        // --------------------------------------------------------
                        // IDLE: Wait for I2C controller to be ready
                        // --------------------------------------------------------
                        IDLE: begin
                            if (i2c_ready) begin
                                state <= DELAY;
                                delay_cnt <= 20'd50000;  // Initial delay ~1ms
                            end
                        end
                        
                        // --------------------------------------------------------
                        // DELAY: Wait specified time before next command
                        // --------------------------------------------------------
                        DELAY: begin
                            if (delay_cnt > 0) begin
                                delay_cnt <= delay_cnt - 1'd1;
                            end else begin
                                state <= SEND;
                            end
                        end
                        
                        // --------------------------------------------------------
                        // SEND: Pulse I2C start signal
                        // --------------------------------------------------------
                        SEND: begin
                            i2c_start <= 1'b1;
                            state <= WAIT;
                        end
                        
                        // --------------------------------------------------------
                        // WAIT: Wait for I2C transaction to complete
                        // --------------------------------------------------------
                        WAIT: begin
                            i2c_start <= 1'b0;
                            
                            if (i2c_ready) begin
                                if (reg_index < NUM_REGS - 1) begin
                                    // More registers to configure
                                    reg_index <= reg_index + 1'd1;
                                    state <= DELAY;
                                    delay_cnt <= 20'd10000;  // Inter-register delay ~200us
                                end else begin
                                    // All registers configured
                                    config_done <= 1'b1;
                                    state <= IDLE;
                                end
                            end
                        end
                        
                        // --------------------------------------------------------
                        // Default: Return to IDLE
                        // --------------------------------------------------------
                        default: state <= IDLE;
                    endcase
                end
            end

        endmodule

        // ===== END wm8731_config.v =====

        // ===== BEGIN wm8731_i2c_controller.v =====

        // ============================================================================
        // I2C Controller for WM8731 Audio Codec Configuration
        // ============================================================================
        // Handles I2C communication for configuring the Wolfson WM8731 chip
        // Supports write transactions to configure codec registers
        // Clock frequency: ~100kHz I2C from 50MHz system clock
        // ============================================================================
        `timescale 1ns/1ps
        module i2c_controller (
            input             clk,          // System clock (50MHz)
            input             reset,        // Active high reset
            input             start,        // Start I2C transaction (pulse)
            input      [6:0]  device_addr,  // 7-bit I2C device address
            input      [15:0] register_data, // 16-bit data to write
            output reg        ready,        // Ready for new transaction
            output reg        i2c_sclk,     // I2C clock output
            inout             i2c_sdat      // I2C bidirectional data
        );

            // ========================================================================
            // I2C Timing Parameters
            // ========================================================================
            // Generate ~100kHz I2C clock from 50MHz system clock
            // 50MHz / 250 = 200kHz toggle rate = 100kHz I2C SCL
            localparam DIVIDER = 250;
            
            // ========================================================================
            // State Machine States
            // ========================================================================
            localparam IDLE       = 4'd0;   // Idle, waiting for start
            localparam START_COND = 4'd1;   // Generate START condition
            localparam ADDR_BYTE  = 4'd2;   // Send device address + R/W bit
            localparam ACK1       = 4'd3;   // Wait for ACK after address
            localparam DATA_HIGH  = 4'd4;   // Send high byte of data
            localparam ACK2       = 4'd5;   // Wait for ACK after high byte
            localparam DATA_LOW   = 4'd6;   // Send low byte of data
            localparam ACK3       = 4'd7;   // Wait for ACK after low byte
            localparam STOP_COND  = 4'd8;   // Generate STOP condition
            localparam DONE       = 4'd9;   // Transaction complete
            
            // ========================================================================
            // Internal Registers
            // ========================================================================
            reg [3:0]  state;           // State machine state
            reg [8:0]  clk_div;         // Clock divider counter
            reg [3:0]  bit_cnt;         // Bit counter for byte transmission
            reg [7:0]  addr_byte;       // Address byte buffer
            reg [7:0]  data_high_byte;  // High byte of data
            reg [7:0]  data_low_byte;   // Low byte of data
            reg        sdat_out;        // SDAT output value
            reg        sdat_oe;         // SDAT output enable (1=drive, 0=tristate)
            
            // ========================================================================
            // Bidirectional Buffer for I2C Data Line
            // ========================================================================
            // Drive SDAT when output enable is high, otherwise tristate for ACK
            assign i2c_sdat = sdat_oe ? sdat_out : 1'bz;
            
            // ========================================================================
            // Main I2C Controller State Machine
            // ========================================================================
            always @(posedge clk or posedge reset) begin
                if (reset) begin
                    // Reset all registers
                    state <= IDLE;
                    ready <= 1'b1;
                    i2c_sclk <= 1'b1;
                    sdat_out <= 1'b1;
                    sdat_oe <= 1'b1;
                    clk_div <= 9'd0;
                    bit_cnt <= 4'd0;
                end else begin
                    // Clock divider for I2C timing
                    clk_div <= clk_div + 1'd1;
                    
                    // Execute state machine at divided clock rate
                    if (clk_div == DIVIDER) begin
                        clk_div <= 9'd0;
                        
                        case (state)
                            // --------------------------------------------------------
                            // IDLE: Wait for start signal
                            // --------------------------------------------------------
                            IDLE: begin
                                ready <= 1'b1;
                                i2c_sclk <= 1'b1;
                                sdat_out <= 1'b1;
                                sdat_oe <= 1'b1;
                                
                                if (start) begin
                                    ready <= 1'b0;
                                    // Prepare data bytes
                                    addr_byte <= {device_addr, 1'b0};  // R/W=0 (write)
                                    data_high_byte <= register_data[15:8];
                                    data_low_byte <= register_data[7:0];
                                    state <= START_COND;
                                end
                            end
                            
                            // --------------------------------------------------------
                            // START_COND: Generate I2C START condition
                            // SDA falls while SCL is high
                            // --------------------------------------------------------
                            START_COND: begin
                                sdat_out <= 1'b0;  // Pull SDA low
                                state <= ADDR_BYTE;
                                bit_cnt <= 4'd7;   // Start from MSB
                            end
                            
                            // --------------------------------------------------------
                            // ADDR_BYTE: Send 8-bit address + R/W
                            // --------------------------------------------------------
                            ADDR_BYTE: begin
                                i2c_sclk <= 1'b0;
                                sdat_out <= addr_byte[bit_cnt];
                                
                                if (bit_cnt == 0) begin
                                    state <= ACK1;
                                end else begin
                                    bit_cnt <= bit_cnt - 1'd1;
                                    i2c_sclk <= 1'b1;
                                end
                            end
                            
                            // --------------------------------------------------------
                            // ACK1: Wait for acknowledgment from slave
                            // --------------------------------------------------------
                            ACK1: begin
                                i2c_sclk <= 1'b0;
                                sdat_oe <= 1'b0;    // Release SDA for slave ACK
                                i2c_sclk <= 1'b1;
                                state <= DATA_HIGH;
                                bit_cnt <= 4'd7;
                            end
                            
                            // --------------------------------------------------------
                            // DATA_HIGH: Send high byte of register data
                            // --------------------------------------------------------
                            DATA_HIGH: begin
                                i2c_sclk <= 1'b0;
                                sdat_oe <= 1'b1;    // Take control of SDA
                                sdat_out <= data_high_byte[bit_cnt];
                                
                                if (bit_cnt == 0) begin
                                    state <= ACK2;
                                end else begin
                                    bit_cnt <= bit_cnt - 1'd1;
                                    i2c_sclk <= 1'b1;
                                end
                            end
                            
                            // --------------------------------------------------------
                            // ACK2: Wait for acknowledgment
                            // --------------------------------------------------------
                            ACK2: begin
                                i2c_sclk <= 1'b0;
                                sdat_oe <= 1'b0;    // Release SDA for slave ACK
                                i2c_sclk <= 1'b1;
                                state <= DATA_LOW;
                                bit_cnt <= 4'd7;
                            end
                            
                            // --------------------------------------------------------
                            // DATA_LOW: Send low byte of register data
                            // --------------------------------------------------------
                            DATA_LOW: begin
                                i2c_sclk <= 1'b0;
                                sdat_oe <= 1'b1;    // Take control of SDA
                                sdat_out <= data_low_byte[bit_cnt];
                                
                                if (bit_cnt == 0) begin
                                    state <= ACK3;
                                end else begin
                                    bit_cnt <= bit_cnt - 1'd1;
                                    i2c_sclk <= 1'b1;
                                end
                            end
                            
                            // --------------------------------------------------------
                            // ACK3: Wait for final acknowledgment
                            // --------------------------------------------------------
                            ACK3: begin
                                i2c_sclk <= 1'b0;
                                sdat_oe <= 1'b0;    // Release SDA for slave ACK
                                i2c_sclk <= 1'b1;
                                state <= STOP_COND;
                            end
                            
                            // --------------------------------------------------------
                            // STOP_COND: Generate I2C STOP condition
                            // SDA rises while SCL is high
                            // --------------------------------------------------------
                            STOP_COND: begin
                                i2c_sclk <= 1'b0;
                                sdat_oe <= 1'b1;
                                sdat_out <= 1'b0;
                                i2c_sclk <= 1'b1;
                                sdat_out <= 1'b1;  // SDA rises (STOP)
                                state <= DONE;
                            end
                            
                            // --------------------------------------------------------
                            // DONE: Transaction complete
                            // --------------------------------------------------------
                            DONE: begin
                                ready <= 1'b1;
                                state <= IDLE;
                            end
                            
                            // --------------------------------------------------------
                            // Default: Return to IDLE
                            // --------------------------------------------------------
                            default: state <= IDLE;
                        endcase
                    end
                end
            end

        endmodule

        // ===== END wm8731_i2c_controller.v =====

        // ===== BEGIN wm8731_i2s_interface.v =====

        // ============================================================================
        // I2S Audio Interface for WM8731 Codec
        // ============================================================================
        // Handles I2S audio streaming with the WM8731 codec
        // Supports 16-bit stereo audio at 48kHz sample rate
        // WM8731 operates in master mode (generates BCLK and LRCK)
        // ============================================================================
        `timescale 1ns/1ps
        module i2s_interface (
            input             clk,           // System clock (50MHz)
            input             reset,         // Active high reset
            
            // I2S signals from/to WM8731 (codec is master)
            input             aud_adclrck,   // ADC Left/Right clock from codec (48kHz)
            input             aud_bclk,      // Bit clock from codec (~3.072MHz)
            input             aud_adcdat,    // ADC serial data input from codec
            output reg        aud_dacdat,    // DAC serial data output to codec
            
            // Parallel audio data interface
            input      [15:0] audio_out_l,   // Left channel output to DAC
            input      [15:0] audio_out_r,   // Right channel output to DAC
            output reg [15:0] audio_in_l,    // Left channel input from ADC
            output reg [15:0] audio_in_r,    // Right channel input from ADC
            output reg        audio_valid    // New audio sample ready (pulse)
        );

            // ========================================================================
            // Clock Domain Crossing Synchronizers
            // ========================================================================
            // Synchronize external I2S signals to system clock domain
            // 3-stage synchronizer for metastability protection
            reg [2:0] bclk_sync;  // Bit clock synchronizer
            reg [2:0] lrck_sync;  // Left/Right clock synchronizer
            
            always @(posedge clk or posedge reset) begin
                if (reset) begin
                    bclk_sync <= 3'b000;
                    lrck_sync <= 3'b000;
                end else begin
                    // Shift in new values
                    bclk_sync <= {bclk_sync[1:0], aud_bclk};
                    lrck_sync <= {lrck_sync[1:0], aud_adclrck};
                end
            end
            
            // ========================================================================
            // Edge and Level Detection
            // ========================================================================
            // Detect edges and levels of synchronized signals
            wire bclk_rising  = (bclk_sync[2:1] == 2'b01);  // Rising edge of BCLK
            wire bclk_falling = (bclk_sync[2:1] == 2'b10);  // Falling edge of BCLK
            wire lrck_edge    = (lrck_sync[2:1] != 2'b00) && (lrck_sync[2:1] != 2'b11);  // Any edge
            wire left_channel = ~lrck_sync[2];              // Left channel when LRCK low
            
            // ========================================================================
            // Internal Shift Registers
            // ========================================================================
            reg [15:0] adc_shift_reg;  // ADC data shift register (serial to parallel)
            reg [15:0] dac_shift_reg;  // DAC data shift register (parallel to serial)
            reg [4:0]  bit_cnt;        // Bit counter (0-15 for 16-bit audio)
            
            // Temporary storage for completed samples
            reg [15:0] adc_left_temp;   // Left channel temporary storage
            reg [15:0] adc_right_temp;  // Right channel temporary storage
            
            // ========================================================================
            // Main I2S Interface Logic
            // ========================================================================
            // Handles serial-to-parallel and parallel-to-serial conversion
            always @(posedge clk or posedge reset) begin
                if (reset) begin
                    // Reset all registers
                    adc_shift_reg <= 16'd0;
                    dac_shift_reg <= 16'd0;
                    bit_cnt <= 5'd0;
                    audio_in_l <= 16'd0;
                    audio_in_r <= 16'd0;
                    aud_dacdat <= 1'b0;
                    audio_valid <= 1'b0;
                    adc_left_temp <= 16'd0;
                    adc_right_temp <= 16'd0;
                end else begin
                    // Default: audio_valid is a single-cycle pulse
                    audio_valid <= 1'b0;
                    
                    // ----------------------------------------------------------------
                    // Channel Switch Detection (LRCK edge)
                    // ----------------------------------------------------------------
                    // LRCK changes indicate start of new channel (left or right)
                    if (lrck_edge) begin
                        bit_cnt <= 5'd15;  // Reset bit counter to MSB
                        
                        if (left_channel) begin
                            // Switching to LEFT channel
                            // Load new DAC data for left channel
                            dac_shift_reg <= audio_out_l;
                            // Store completed RIGHT channel ADC data
                            audio_in_r <= adc_shift_reg;
                            // Pulse audio_valid to indicate new sample pair ready
                            audio_valid <= 1'b1;
                        end else begin
                            // Switching to RIGHT channel
                            // Load new DAC data for right channel
                            dac_shift_reg <= audio_out_r;
                            // Store completed LEFT channel ADC data
                            audio_in_l <= adc_shift_reg;
                        end
                    end
                    
                    // ----------------------------------------------------------------
                    // DAC Data Transmission (on BCLK falling edge)
                    // ----------------------------------------------------------------
                    // Shift out DAC data MSB first
                    // WM8731 master mode: sample DAC data on BCLK falling edge
                    else if (bclk_falling && bit_cnt < 16) begin
                        // Output current MSB
                        aud_dacdat <= dac_shift_reg[15];
                        // Shift left (next bit to MSB position)
                        dac_shift_reg <= {dac_shift_reg[14:0], 1'b0};
                        // Decrement bit counter
                        bit_cnt <= bit_cnt - 1'd1;
                    end
                    
                    // ----------------------------------------------------------------
                    // ADC Data Reception (on BCLK rising edge)
                    // ----------------------------------------------------------------
                    // Shift in ADC data MSB first
                    // WM8731 master mode: ADC data valid on BCLK rising edge
                    else if (bclk_rising && bit_cnt < 16) begin
                        // Shift in new bit from ADC
                        adc_shift_reg <= {adc_shift_reg[14:0], aud_adcdat};
                    end
                end
            end

        endmodule

        // ===== END wm8731_i2s_interface.v =====
