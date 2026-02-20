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
