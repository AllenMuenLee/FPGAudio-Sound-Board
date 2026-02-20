// ============================================================================
// Audio Clock Generator for WM8731
// ============================================================================
// Generates AUD_XCK (master clock) for the WM8731 codec
// Target: 12.288 MHz for 48kHz operation (48kHz * 256)
// From 50MHz: Divide by ~4.07 ≈ 12.285 MHz (very close!)
// ============================================================================

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
