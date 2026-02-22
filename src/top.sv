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
    
    noise_gate ng_inst (.clk(clk), .audio_in(audio_in), .audio_out(noise_gate_out));
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
// ============================================================================
// High Pitch Audio Effect Module
// ============================================================================
// Description:
//   Creates a high-pitch (chipmunk) effect by periodically skipping audio
//   samples. This effectively doubles the playback speed without changing the
//   sample rate, resulting in a higher perceived pitch.
//
// Operation:
//   - Alternates between passing input samples and holding previous samples
//   - Each phase lasts for HIGH_PITCH_PERIOD clock cycles (1042 cycles)
//   - During "pass-through" phase: outputs current input sample
//   - During "hold" phase: outputs the last captured sample
//   - Result: plays audio at 2x speed, shifting pitch up one octave
//
// Technical Details:
//   - At 48 kHz sample rate: 1042 cycles ≈ 21.7 ms per phase
//   - Full cycle time: ~43.4 ms (23 Hz switching rate)
//   - Pitch shift: approximately +12 semitones (one octave up)
//
// ============================================================================
`timescale 1ns/1ps
module high_pitch_effect (
    input  wire        clk,          // System clock
    input  wire        reset,        // Active-high synchronous reset
    input  wire [15:0] audio_in,     // 16-bit audio input
    output reg  [15:0] audio_out     // 16-bit audio output
);

    // ========================================================================
    // Parameter Definitions
    // ========================================================================
    
    // Period for phase switching (1042 clock cycles per phase)
    localparam HIGH_PITCH_PERIOD = 1042;
    
    // ========================================================================
    // Internal Registers
    // ========================================================================
    
    // Counter to track phase timing (0 to HIGH_PITCH_PERIOD-1)
    reg [10:0] counter;
    
    // Phase control: 0 = pass-through mode, 1 = hold mode
    reg hold;
    
    // Storage for the sample to hold during hold phase
    reg [15:0] held_sample;
    
    // ========================================================================
    // Main Processing Logic
    // ========================================================================
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // ================================================================
            // Reset: Initialize all registers to default values
            // ================================================================
            counter      <= 11'd0;
            hold         <= 1'b0;      // Start in pass-through mode
            held_sample  <= 16'd0;
            audio_out    <= 16'd0;
            
        end else begin
            // ================================================================
            // Phase Timing and Sample Capture
            // ================================================================
            
            if (counter >= HIGH_PITCH_PERIOD - 1) begin
                // End of current phase - reset counter and toggle mode
                counter <= 11'd0;
                hold <= ~hold;
                
                // Capture input sample at the end of hold phase
                // (This becomes the held sample for the next hold phase)
                if (hold) 
                    held_sample <= audio_in;
                    
            end else begin
                // Continue current phase - increment counter
                counter <= counter + 1'd1;
            end
            
            // ================================================================
            // Output Selection
            // ================================================================
            // Output held sample during hold mode, or pass input through
            audio_out <= hold ? held_sample : audio_in;
        end
    end
    
endmodule
// ============================================================================
// Low Pitch Audio Effect Module
// ============================================================================
// Description:
//   Creates a low-pitch (deep voice) effect by repeating audio samples.
//   This effectively slows down playback speed without changing the sample
//   rate, resulting in a lower perceived pitch.
//
// Operation:
//   - Alternates between capturing new samples and repeating held samples
//   - Each phase lasts for LOW_PITCH_PERIOD clock cycles (2084 cycles)
//   - During "capture" phase: grabs a fresh input sample
//   - During "repeat" phase: continues outputting the held sample
//   - Result: plays audio at 0.5x speed, shifting pitch down one octave
//
// Technical Details:
//   - At 48 kHz sample rate: 2084 cycles ≈ 43.4 ms per phase
//   - Full cycle time: ~86.8 ms (11.5 Hz switching rate)
//   - Pitch shift: approximately -12 semitones (one octave down)
//   - 2× period of high pitch effect for symmetrical octave shift
//
// ============================================================================
`timescale 1ns/1ps
module low_pitch_effect (
    input  wire        clk,          // System clock
    input  wire        reset,        // Active-high synchronous reset
    input  wire [15:0] audio_in,     // 16-bit audio input
    output reg  [15:0] audio_out     // 16-bit audio output
);

    // ========================================================================
    // Parameter Definitions
    // ========================================================================
    
    // Period for phase switching (2084 clock cycles per phase)
    // This is 2× the high pitch period for inverse effect
    localparam LOW_PITCH_PERIOD = 2084;
    
    // ========================================================================
    // Internal Registers
    // ========================================================================
    
    // Counter to track phase timing (0 to LOW_PITCH_PERIOD-1)
    reg [11:0] counter;
    
    // Phase control: 0 = capture new sample, 1 = repeat held sample
    reg repeat_sig;
    
    // Storage for the sample to repeat during repeat phase
    reg [15:0] held_sample;
    
    // ========================================================================
    // Main Processing Logic
    // ========================================================================
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // ================================================================
            // Reset: Initialize all registers to default values
            // ================================================================
            counter      <= 12'd0;
            repeat_sig   <= 1'b0;      // Start in capture mode
            held_sample  <= 16'd0;
            audio_out    <= 16'd0;
            
        end else begin
            // ================================================================
            // Phase Timing and Sample Capture
            // ================================================================
            
            if (counter >= LOW_PITCH_PERIOD - 1) begin
                // End of current phase - reset counter and toggle mode
                counter <= 12'd0;
                repeat_sig <= ~repeat_sig;
                
                // Capture new input sample at the end of capture phase
                // (This becomes the held sample for the entire next repeat phase)
                if (!repeat_sig) 
                    held_sample <= audio_in;
                    
            end else begin
                // Continue current phase - increment counter
                counter <= counter + 1'd1;
            end
            
            // ================================================================
            // Output Generation
            // ================================================================
            // Always output the held sample (updated during capture phase)
            // This creates the sample repetition that lowers pitch
            audio_out <= held_sample;
        end
    end
    
endmodule
// ============================================================================
// Muffled Audio Effect Module (Low-Pass Filter)
// ============================================================================
// Description:
//   Implements a simple 4-tap FIR (Finite Impulse Response) low-pass filter
//   that creates a "muffled" or "underwater" sound by attenuating high
//   frequencies while preserving low frequencies. Uses a moving average
//   technique with sign extension for proper signed arithmetic.
//
// Operation:
//   - Maintains a 4-sample delay line (current + 3 previous samples)
//   - Computes average of all 4 samples each clock cycle
//   - Averages naturally smooth out rapid changes (high frequencies)
//   - Preserves slower variations (low frequencies)
//   - Result: removes treble, emphasizes bass (muffled character)
//
// Technical Details:
//   - Filter type: 4-tap moving average (box filter)
//   - Cutoff frequency: ~12 kHz at 48 kHz sample rate
//   - Attenuation: -6 dB per octave above cutoff
//   - Delay: 3 samples latency (~62.5 μs at 48 kHz)
//   - Arithmetic: Sign-extended to 18 bits to prevent overflow
//
// Audio Quality:
//   - Smooth, gentle roll-off of high frequencies
//   - No ringing artifacts (simple averaging)
//   - Computationally efficient (only additions and shifts)
//
// ============================================================================
`timescale 1ns/1ps
module muffled_effect (
    input  wire        clk,          // System clock
    input  wire        reset,        // Active-high synchronous reset
    input  wire [15:0] audio_in,     // 16-bit audio input
    output reg  [15:0] audio_out     // 16-bit audio output
);

    // ========================================================================
    // Internal Registers
    // ========================================================================
    
    // Delay line: 3 previous samples
    reg [15:0] prev1;    // Previous sample (t-1)
    reg [15:0] prev2;    // 2 samples ago (t-2)
    reg [15:0] prev3;    // 3 samples ago (t-3)
    
    // Sum of all 4 samples (18-bit to prevent overflow during addition)
    reg [17:0] sum;
    
    // ========================================================================
    // Main Processing Logic
    // ========================================================================
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // ================================================================
            // Reset: Clear delay line and output
            // ================================================================
            prev1     <= 16'd0;
            prev2     <= 16'd0;
            prev3     <= 16'd0;
            audio_out <= 16'd0;
            
        end else begin
            // ================================================================
            // Stage 1: Shift delay line (register pipeline)
            // ================================================================
            // Move samples through the delay line (FIFO behavior)
            prev3 <= prev2;
            prev2 <= prev1;
            prev1 <= audio_in;
            
            // ================================================================
            // Stage 2: Compute sum of 4 samples with sign extension
            // ================================================================
            // Sign-extend each 16-bit sample to 18 bits before adding
            // Replicating MSB twice: {sign, sign, data[15:0]}
            // This preserves sign for correct signed arithmetic
            sum = {audio_in[15], audio_in[15], audio_in} +
                  {prev1[15],    prev1[15],    prev1}    +
                  {prev2[15],    prev2[15],    prev2}    +
                  {prev3[15],    prev3[15],    prev3};
            
            // ================================================================
            // Stage 3: Divide by 4 to get average
            // ================================================================
            // Right shift by 2 bits: sum >> 2 = sum / 4
            // This computes the average of the 4 samples
            // Taking bits [17:2] effectively divides by 4 and truncates to 16 bits
            audio_out <= sum[17:2];
        end
    end
    
endmodule
// ============================================================================
// Noise Gate Audio Effect Module
// ============================================================================
// Description:
//   Implements a dynamic noise gate that attenuates quiet audio signals below
//   a threshold while allowing louder signals to pass through. Uses hysteresis
//   to prevent rapid switching and smooth attack/release ramping for natural
//   dynamics.
//
// Operation:
//   - Monitors absolute amplitude of incoming audio
//   - Opens gate when signal exceeds OPEN_THR (1000)
//   - Closes gate when signal falls below CLOSE_THR (500)
//   - Applies variable gain (10% to 100%) with smooth transitions
//   - Fast attack (10 steps) for quick response to loud signals
//   - Slow release (1 step) for natural fade-out of quiet signals
//
// Parameters:
//   - OPEN_THR:  Threshold to open gate (1000 = ~3% of max amplitude)
//   - CLOSE_THR: Threshold to close gate (500 = ~1.5% of max amplitude)
//   - GAIN_MAX:  Maximum gain = 1023 (100% signal pass-through)
//   - GAIN_MIN:  Minimum gain = 102 (~10% attenuation floor)
//   - ATK_STEP:  Attack increment = 10 (fast gain increase)
//   - RLS_STEP:  Release decrement = 1 (slow gain decrease)
//
// ============================================================================
`timescale 1ns/1ps
module noise_gate (
    input  wire        clk,          // System clock
    input  wire signed [15:0] audio_in,   // Signed 16-bit audio input
    output reg  signed [15:0] audio_out   // Signed 16-bit audio output
);

    // ========================================================================
    // Parameter Definitions
    // ========================================================================
    
    // Threshold for gate to open (signal must exceed this)
    localparam signed [15:0] OPEN_THR  = 16'd1000;
    
    // Threshold for gate to close (signal must drop below this)
    localparam signed [15:0] CLOSE_THR = 16'd500;
    
    // Maximum gain value (100% = full signal)
    localparam [9:0] GAIN_MAX = 10'd1023;
    
    // Minimum gain value (~10% = attenuated signal)
    localparam [9:0] GAIN_MIN = 10'd102;
    
    // Attack step size (how fast gain increases when gate opens)
    localparam [9:0] ATK_STEP = 10'd10;
    
    // Release step size (how slow gain decreases when gate closes)
    localparam [9:0] RLS_STEP = 10'd1;
    
    // ========================================================================
    // Internal Registers
    // ========================================================================
    
    // Current gain value (10-bit for 0.1% precision)
    reg [9:0] gain = 10'd102;
    
    // Gate state: 1 = open (signal passing), 0 = closed (attenuated)
    reg is_open = 1'b0;
    
    // Absolute value of input audio for threshold comparison
    reg [15:0] abs_v;
    
    // Multiplication result before scaling (26-bit to hold product)
    reg signed [25:0] mult_result;
    
    // ========================================================================
    // Main Processing Logic
    // ========================================================================
    
    always @(posedge clk) begin
        // ====================================================================
        // Stage 1: Calculate absolute value of input signal
        // ====================================================================
        // If MSB is 1 (negative), negate; otherwise keep as-is
        abs_v <= (audio_in[15]) ? -audio_in : audio_in;
        
        // ====================================================================
        // Stage 2: Gate state machine with hysteresis
        // ====================================================================
        // Open gate if signal exceeds upper threshold
        if (abs_v > OPEN_THR) 
            is_open <= 1'b1;
        // Close gate if signal drops below lower threshold
        else if (abs_v < CLOSE_THR) 
            is_open <= 1'b0;
        // Stay in current state if between thresholds (hysteresis)
        
        // ====================================================================
        // Stage 3: Gain ramping (attack/release envelope)
        // ====================================================================
        if (is_open) begin
            // Attack: quickly ramp up gain when gate opens
            if (gain < (GAIN_MAX - ATK_STEP)) 
                gain <= gain + ATK_STEP;
            else 
                gain <= GAIN_MAX;
        end else begin
            // Release: slowly ramp down gain when gate closes
            if (gain > (GAIN_MIN + RLS_STEP)) 
                gain <= gain - RLS_STEP;
            else 
                gain <= GAIN_MIN;
        end
        
        // ====================================================================
        // Stage 4: Apply gain to input signal
        // ====================================================================
        // Multiply audio by gain (signed audio × unsigned gain)
        mult_result <= audio_in * $signed({1'b0, gain});
        
        // Scale down by dividing by 1024 (shift right 10 bits)
        // This normalizes gain of 1023 to ~1.0 (unity gain)
        audio_out <= mult_result[25:10];
    end
    
endmodule
// ============================================================================
// Reverb Audio Effect Module
// ============================================================================
// Description:
//   Implements a simple digital reverb effect using a circular delay buffer
//   with feedback. Creates the illusion of sound reflecting in a space by
//   mixing delayed copies of the audio signal back into itself.
//
// Operation:
//   - Maintains a 512-sample circular buffer as a delay line
//   - Reads delayed audio from buffer and mixes it back with 25% attenuation
//   - Writes current input plus 25% of delayed signal back to buffer
//   - Creates repeating echoes that simulate room reflections
//   - Implements overflow protection to prevent clipping
//
// Technical Details:
//   - Delay length: 512 samples ≈ 10.7 ms at 48 kHz
//   - Feedback gain: 0.25 (>>> 2 = divide by 4)
//   - Wet mix: 0.25 (delayed signal contribution to output)
//   - Dry mix: 1.0 (original signal contribution to output)
//   - Total output: dry + 0.25×wet with saturation protection
//
// Audio Quality:
//   - Short delay creates a "small room" reverb character
//   - Feedback extends the reverb tail naturally
//   - Prevents harsh clipping with overflow detection
//
// ============================================================================
`timescale 1ns/1ps
module reverb_effect (
    input  wire        clk,          // System clock
    input  wire        reset,        // Active-high synchronous reset
    input  wire [15:0] audio_in,     // 16-bit audio input
    output reg  [15:0] audio_out     // 16-bit audio output
);

    // ========================================================================
    // Parameter Definitions
    // ========================================================================
    
    // Length of delay buffer (512 samples = ~10.7 ms at 48 kHz)
    localparam DELAY_LENGTH = 512;
    
    // ========================================================================
    // Internal Registers and Memory
    // ========================================================================
    
    // Circular delay buffer (512 × 16-bit samples)
    reg [15:0] delay_buffer [0:DELAY_LENGTH-1];
    
    // Write pointer for circular buffer (0 to 511)
    reg [8:0] write_ptr;
    
    // Read pointer for circular buffer (0 to 511)
    reg [8:0] read_ptr;
    
    // Delayed audio sample read from buffer
    reg [15:0] delay_out;
    
    // Mixed audio before saturation (17-bit to detect overflow)
    reg [16:0] mix;
    
    // ========================================================================
    // Main Processing Logic
    // ========================================================================
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // ================================================================
            // Reset: Initialize pointers and outputs
            // ================================================================
            write_ptr <= 9'd0;
            read_ptr  <= 9'd0;
            delay_out <= 16'd0;
            audio_out <= 16'd0;
            // Note: delay_buffer contents are not explicitly reset
            //       (will naturally fill with valid data during operation)
            
        end else begin
            // ================================================================
            // Stage 1: Write to delay buffer with feedback
            // ================================================================
            // Write input plus 25% of delayed signal (creates feedback loop)
            // >>> 2 performs arithmetic right shift (divide by 4 = 0.25 gain)
            delay_buffer[write_ptr] <= audio_in + (delay_out >>> 2);
            
            // ================================================================
            // Stage 2: Read from delay buffer
            // ================================================================
            // Fetch the delayed sample from read position
            delay_out <= delay_buffer[read_ptr];
            
            // ================================================================
            // Stage 3: Mix dry and wet signals with overflow protection
            // ================================================================
            // Combine original signal with 25% of delayed signal
            // Sign-extend audio_in to 17 bits for overflow detection
            mix = {audio_in[15], audio_in} + ({delay_out[15], delay_out} >>> 2);
            
            // Check for overflow and apply saturation
            if (mix[16:15] == 2'b01) 
                // Positive overflow: clamp to maximum positive value
                audio_out <= 16'h7FFF;
            else if (mix[16:15] == 2'b10) 
                // Negative overflow: clamp to maximum negative value
                audio_out <= 16'h8000;
            else 
                // No overflow: output mixed signal
                audio_out <= mix[15:0];
            
            // ================================================================
            // Stage 4: Update circular buffer pointers
            // ================================================================
            // Increment both pointers (auto-wraps at 512 due to 9-bit width)
            write_ptr <= write_ptr + 1'd1;
            read_ptr  <= read_ptr + 1'd1;
        end
    end
    
endmodule
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
