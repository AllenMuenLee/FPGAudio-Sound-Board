module noise_gate (
    input  wire        clk,
    input  wire signed [15:0] audio_in,
    output reg  signed [15:0] audio_out
);

    // Fixed-point parameters (10-bit fractional precision)
    localparam signed [15:0] OPEN_THR  = 16'd1000; //1000 db
    localparam signed [15:0] CLOSE_THR = 16'd500; // 500 db
    localparam [9:0]         GAIN_MAX  = 10'd1024;
    localparam [9:0]         GAIN_MIN  = 10'd102;
    localparam [9:0]         ATK_STEP  = 10'd10;
    localparam [9:0]         RLS_STEP  = 10'd1;

    reg [9:0]  gain = 10'd102; // Start at floor
    reg        is_open = 0;
    reg [15:0] abs_v;
    reg signed [25:0] mult_result; // Intermediate 26-bit product

    always @(posedge clk) begin
        // 1. Calculate Absolute Value
        abs_v <= (audio_in[15]) ? -audio_in : audio_in;

        // 2. Hysteresis State Logic
        if (abs_v > OPEN_THR)
            is_open <= 1'b1;
        else if (abs_v < CLOSE_THR)
            is_open <= 1'b0;

        // 3. Gain Smoothing (Attack/Release)
        if (is_open) begin
            if (gain < (GAIN_MAX - ATK_STEP))
                gain <= gain + ATK_STEP;
            else
                gain <= GAIN_MAX;
        end else begin
            if (gain > (GAIN_MIN + RLS_STEP))
                gain <= gain - RLS_STEP;
            else
                gain <= GAIN_MIN;
        end

        // 4. Apply Gain (Fixed-Point Multiplication)
        mult_result <= audio_in * $signed({1'b0, gain});
        
        // 5. Shift back to 16-bit (Divide by 1024)
        audio_out <= mult_result[25:10];
    end
endmodule

module audio_processor (
    input             clk,          // 50MHz system clock
    input             reset,        // Active high reset
    input      [15:0] audio_in,     // 16-bit signed audio input
    input      [9:0]  SW,           // Switch inputs (using SW[2:0] for effect select)
    output reg [15:0] audio_out     // 16-bit signed audio output
);

    // Effect selection from switches
    wire [2:0] effect_select;
    assign effect_select = SW[2:0];
    
    // ========================================================================
    // High Pitch: Sample Rate Manipulation
    // ========================================================================
    // Creates pitch shift by periodically skipping samples
    // Faster playback = higher pitch
    // ========================================================================
    localparam HIGH_PITCH_PERIOD = 1042;  // ~48kHz at 50MHz clock
    
    reg [10:0] high_pitch_counter;  // Counter for sample rate (needs 11 bits for 1042)
    reg        high_pitch_hold;     // Sample hold signal
    reg [15:0] high_pitch_sample;   // Held sample for pitch shift
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            high_pitch_counter <= 11'd0;
            high_pitch_hold <= 1'b0;
            high_pitch_sample <= 16'd0;
        end else begin
            if (high_pitch_counter >= HIGH_PITCH_PERIOD - 1) begin
                high_pitch_counter <= 11'd0;
                high_pitch_hold <= ~high_pitch_hold;  // Toggle hold
                if (high_pitch_hold) begin
                    high_pitch_sample <= audio_in;  // Capture new sample
                end
            end else begin
                high_pitch_counter <= high_pitch_counter + 1'd1;
            end
        end
    end
    
    // ========================================================================
    // Low Pitch: Sample Repetition
    // ========================================================================
    // Creates pitch shift by repeating samples
    // Slower playback = lower pitch
    // ========================================================================
    localparam LOW_PITCH_PERIOD = 2084;  // Double the high pitch period
    
    reg [11:0] low_pitch_counter;   // Counter for sample rate (needs 12 bits for 2084)
    reg        low_pitch_repeat;    // Sample repeat signal
    reg [15:0] low_pitch_sample;    // Held sample for pitch shift
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            low_pitch_counter <= 12'd0;
            low_pitch_repeat <= 1'b0;
            low_pitch_sample <= 16'd0;
        end else begin
            if (low_pitch_counter >= LOW_PITCH_PERIOD - 1) begin
                low_pitch_counter <= 12'd0;
                low_pitch_repeat <= ~low_pitch_repeat;  // Toggle repeat
                if (!low_pitch_repeat) begin
                    low_pitch_sample <= audio_in;  // Capture new sample
                end
            end else begin
                low_pitch_counter <= low_pitch_counter + 1'd1;
            end
        end
    end
    
    // ========================================================================
    // Reverb: Delay Line Buffer
    // ========================================================================
    // Creates echo/reverb effect using a circular delay buffer
    // Delay time: ~10ms (512 samples)
    // ========================================================================
    localparam DELAY_LENGTH = 512;  // Power of 2 for simple addressing
    
    reg [15:0] delay_buffer [0:DELAY_LENGTH-1];  // Circular buffer for delay
    reg [8:0]  delay_write_ptr;                   // Write pointer (9 bits for 512)
    reg [8:0]  delay_read_ptr;                    // Read pointer
    reg [15:0] delay_output;                      // Output from delay line
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            delay_write_ptr <= 9'd0;
            delay_read_ptr <= 9'd0;
            delay_output <= 16'd0;
        end else begin
            // Write current input mixed with feedback to delay buffer
            delay_buffer[delay_write_ptr] <= audio_in + (delay_output >>> 2);  // 25% feedback
            
            // Read from delay buffer (fixed delay)
            delay_output <= delay_buffer[delay_read_ptr];
            
            // Increment pointers (circular buffer)
            delay_write_ptr <= delay_write_ptr + 1'd1;
            delay_read_ptr <= delay_read_ptr + 1'd1;
        end
    end
    
    // ========================================================================
    // Muffled: Low-Pass Filter
    // ========================================================================
    // Averages current and previous samples to filter high frequencies
    // Creates underwater/telephone-like sound
    // ========================================================================
    reg [15:0] muffled_prev1;  // Previous sample 1
    reg [15:0] muffled_prev2;  // Previous sample 2
    reg [15:0] muffled_prev3;  // Previous sample 3
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            muffled_prev1 <= 16'd0;
            muffled_prev2 <= 16'd0;
            muffled_prev3 <= 16'd0;
        end else begin
            // Shift register for previous samples
            muffled_prev3 <= muffled_prev2;
            muffled_prev2 <= muffled_prev1;
            muffled_prev1 <= audio_in;
        end
    end
    
    // ========================================================================
    // Effect Processing
    // ========================================================================
    // Process audio input based on selected effect
    // ========================================================================
    
    reg [15:0] processed_audio;  // Intermediate processed audio
    reg [15:0] abs_audio;        // Absolute value of audio for noise gate
    reg [16:0] reverb_mix;       // Temporary for reverb mixing (17 bits for overflow)
    reg [17:0] muffled_sum;      // Temporary for muffled averaging (18 bits for sum of 4 samples)
    
    always @(*) begin
        case (effect_select)
            // ----------------------------------------------------------------
            // Effect 0: Noise Gate
            // Strips background noise by muting signals below threshold
            // Threshold set at 2048 (about 6% of max amplitude)
            // Only passes audio when signal is above noise floor
            // ----------------------------------------------------------------
            3'b000: begin
                // Calculate absolute value for threshold comparison
                abs_audio = (audio_in[15]) ? -audio_in : audio_in;
                
                // If signal is above threshold, pass it through; otherwise mute
                if (abs_audio > 16'd2048) begin
                    processed_audio = audio_in;  // Signal detected, pass through
                end else begin
                    processed_audio = 16'd0;  // Below threshold, mute (strip noise)
                end
            end
            
            // ----------------------------------------------------------------
            // Effect 1: High Pitch (Helium Voice)
            // Creates high-pitched voice effect like helium inhalation
            // Uses sample-and-hold to simulate higher pitch
            // Alternates between current and held sample for pitch shift
            // ----------------------------------------------------------------
            3'b001: begin
                if (high_pitch_hold) begin
                    processed_audio = high_pitch_sample;  // Use held sample
                end else begin
                    processed_audio = audio_in;  // Use current sample
                end
            end
            
            // ----------------------------------------------------------------
            // Effect 2: Low Pitch (Deep Voice)
            // Creates low-pitched voice effect (opposite of helium)
            // Repeats samples to slow down playback
            // ----------------------------------------------------------------
            3'b010: begin
                if (low_pitch_repeat) begin
                    processed_audio = low_pitch_sample;  // Repeat held sample
                end else begin
                    processed_audio = low_pitch_sample;  // Use held sample
                end
            end
            
            // ----------------------------------------------------------------
            // Effect 3: Reverb (Echo/Spatial Depth)
            // Mixes original signal with delayed version to create echoes
            // Uses feedback for multiple reflections
            // Creates spacious, room-like acoustics
            // ----------------------------------------------------------------
            3'b011: begin
                // Mix dry signal (75%) with wet signal (25%)
                reverb_mix = {audio_in[15], audio_in} + (delay_output >>> 2);
                
                // Clamp to prevent overflow
                if (reverb_mix[16:15] == 2'b01)  // Positive overflow
                    processed_audio = 16'h7FFF;
                else if (reverb_mix[16:15] == 2'b10)  // Negative overflow
                    processed_audio = 16'h8000;
                else
                    processed_audio = reverb_mix[15:0];
            end
            
            // ----------------------------------------------------------------
            // Effect 4: Muffled (Low-Pass Filter)
            // Averages current and 3 previous samples
            // Removes high frequencies for underwater/telephone sound
            // Creates muffled, distant sound effect
            // ----------------------------------------------------------------
            3'b100: begin
                // Average 4 samples (divide by 4 = right shift by 2)
                muffled_sum = {audio_in[15], audio_in[15], audio_in} + 
                              {muffled_prev1[15], muffled_prev1[15], muffled_prev1} +
                              {muffled_prev2[15], muffled_prev2[15], muffled_prev2} +
                              {muffled_prev3[15], muffled_prev3[15], muffled_prev3};
                
                processed_audio = muffled_sum[17:2];  // Divide by 4 (right shift 2)
            end
            
            // ----------------------------------------------------------------
            // Default: Pass through
            // ----------------------------------------------------------------
            default: begin
                processed_audio = audio_in;
            end
        endcase
    end
    
    // ========================================================================
    // Output Register
    // ========================================================================
    // Register the output for better timing
    // ========================================================================
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            audio_out <= 16'd0;
        end else begin
            audio_out <= processed_audio;
        end
    end

endmodule