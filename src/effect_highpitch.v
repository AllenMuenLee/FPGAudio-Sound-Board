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
