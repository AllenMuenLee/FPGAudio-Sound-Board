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
