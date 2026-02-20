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
