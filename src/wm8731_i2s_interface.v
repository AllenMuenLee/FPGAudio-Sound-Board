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
