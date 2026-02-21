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
    
    noise_gate ng_inst (.clk(clk), .reset(reset), .audio_in(audio_in), .audio_out(noise_gate_out));
    high_pitch_effect hp_inst (.clk(clk), .reset(reset), .audio_in(audio_in), .audio_out(high_pitch_out));
    low_pitch_effect lp_inst (.clk(clk), .reset(reset), .audio_in(audio_in), .audio_out(low_pitch_out));
    reverb_effect rev_inst (.clk(clk), .reset(reset), .audio_in(audio_in), .audio_out(reverb_out));
    muffled_effect muf_inst (.clk(clk), .reset(reset), .audio_in(audio_in), .audio_out(muffled_out));
    
    always @(posedge clk or posedge reset) begin
        if (reset) audio_out <= 16'd0;
        else begin
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
