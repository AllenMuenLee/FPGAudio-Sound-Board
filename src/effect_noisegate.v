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
