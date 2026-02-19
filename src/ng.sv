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