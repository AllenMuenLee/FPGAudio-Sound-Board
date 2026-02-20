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
