// ============================================================================
// Multi-Effect Audio Processor for DE1-SoC Board - Modular Design
// ============================================================================
// Each audio effect is implemented as a separate module for better organization
// Compatible with DE1-SoC board audio system (50MHz clock, 16-bit audio)
//
// Switch Control (SW[2:0]):
//   3'b000 = Noise Gate (professional implementation)
//   3'b001 = High Pitch (helium voice)
//   3'b010 = Low Pitch (deep voice)
//   3'b011 = Reverb (echo/spatial depth)
//   3'b100 = Muffled (low-pass filter)
// ============================================================================

// ============================================================================
// MODULE 1: Noise Gate Effect
// ============================================================================
module noise_gate (
    input  wire        clk,
    input  wire signed [15:0] audio_in,
    output reg  signed [15:0] audio_out
);
    localparam signed [15:0] OPEN_THR  = 16'd1000;
    localparam signed [15:0] CLOSE_THR = 16'd500;
    localparam [9:0] GAIN_MAX = 10'd1023;
    localparam [9:0] GAIN_MIN = 10'd102;
    localparam [9:0] ATK_STEP = 10'd10;
    localparam [9:0] RLS_STEP = 10'd1;
    
    reg [9:0] gain = 10'd102;
    reg is_open = 1'b0;
    reg [15:0] abs_v;
    reg signed [25:0] mult_result;
    
    always @(posedge clk) begin
        abs_v <= (audio_in[15]) ? -audio_in : audio_in;
        if (abs_v > OPEN_THR) is_open <= 1'b1;
        else if (abs_v < CLOSE_THR) is_open <= 1'b0;
        if (is_open) begin
            if (gain < (GAIN_MAX - ATK_STEP)) gain <= gain + ATK_STEP;
            else gain <= GAIN_MAX;
        end else begin
            if (gain > (GAIN_MIN + RLS_STEP)) gain <= gain - RLS_STEP;
            else gain <= GAIN_MIN;
        end
        mult_result <= audio_in * $signed({1'b0, gain});
        audio_out <= mult_result[25:10];
    end
endmodule

// ============================================================================
// MODULE 2: High Pitch Effect
// ============================================================================
module high_pitch_effect (
    input  wire        clk,
    input  wire        reset,
    input  wire [15:0] audio_in,
    output reg  [15:0] audio_out
);
    localparam HIGH_PITCH_PERIOD = 1042;
    reg [10:0] counter;
    reg hold;
    reg [15:0] held_sample;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            counter <= 11'd0;
            hold <= 1'b0;
            held_sample <= 16'd0;
            audio_out <= 16'd0;
        end else begin
            if (counter >= HIGH_PITCH_PERIOD - 1) begin
                counter <= 11'd0;
                hold <= ~hold;
                if (hold) held_sample <= audio_in;
            end else counter <= counter + 1'd1;
            audio_out <= hold ? held_sample : audio_in;
        end
    end
endmodule

// ============================================================================
// MODULE 3: Low Pitch Effect
// ============================================================================
module low_pitch_effect (
    input  wire        clk,
    input  wire        reset,
    input  wire [15:0] audio_in,
    output reg  [15:0] audio_out
);
    localparam LOW_PITCH_PERIOD = 2084;
    reg [11:0] counter;
    reg repeat_sig;
    reg [15:0] held_sample;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            counter <= 12'd0;
            repeat_sig <= 1'b0;
            held_sample <= 16'd0;
            audio_out <= 16'd0;
        end else begin
            if (counter >= LOW_PITCH_PERIOD - 1) begin
                counter <= 12'd0;
                repeat_sig <= ~repeat_sig;
                if (!repeat_sig) held_sample <= audio_in;
            end else counter <= counter + 1'd1;
            audio_out <= held_sample;
        end
    end
endmodule

// ============================================================================
// MODULE 4: Reverb Effect
// ============================================================================
module reverb_effect (
    input  wire        clk,
    input  wire        reset,
    input  wire [15:0] audio_in,
    output reg  [15:0] audio_out
);
    localparam DELAY_LENGTH = 512;
    reg [15:0] delay_buffer [0:DELAY_LENGTH-1];
    reg [8:0] write_ptr;
    reg [8:0] read_ptr;
    reg [15:0] delay_out;
    reg [16:0] mix;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            write_ptr <= 9'd0;
            read_ptr <= 9'd0;
            delay_out <= 16'd0;
            audio_out <= 16'd0;
        end else begin
            delay_buffer[write_ptr] <= audio_in + (delay_out >>> 2);
            delay_out <= delay_buffer[read_ptr];
            mix = {audio_in[15], audio_in} + (delay_out >>> 2);
            if (mix[16:15] == 2'b01) audio_out <= 16'h7FFF;
            else if (mix[16:15] == 2'b10) audio_out <= 16'h8000;
            else audio_out <= mix[15:0];
            write_ptr <= write_ptr + 1'd1;
            read_ptr <= read_ptr + 1'd1;
        end
    end
endmodule

// ============================================================================
// MODULE 5: Muffled Effect
// ============================================================================
module muffled_effect (
    input  wire        clk,
    input  wire        reset,
    input  wire [15:0] audio_in,
    output reg  [15:0] audio_out
);
    reg [15:0] prev1, prev2, prev3;
    reg [17:0] sum;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            prev1 <= 16'd0;
            prev2 <= 16'd0;
            prev3 <= 16'd0;
            audio_out <= 16'd0;
        end else begin
            prev3 <= prev2;
            prev2 <= prev1;
            prev1 <= audio_in;
            sum = {audio_in[15], audio_in[15], audio_in} +
                  {prev1[15], prev1[15], prev1} +
                  {prev2[15], prev2[15], prev2} +
                  {prev3[15], prev3[15], prev3};
            audio_out <= sum[17:2];
        end
    end
endmodule

// ============================================================================
// MODULE 6: Audio Processor (Top Level)
// ============================================================================
module audio_processor (
    input             clk,
    input             reset,
    input      [15:0] audio_in,
    input      [9:0]  SW,
    output reg [15:0] audio_out
);
    wire [2:0] effect_select;
    assign effect_select = SW[2:0];
    
    wire [15:0] noise_gate_out;
    wire [15:0] high_pitch_out;
    wire [15:0] low_pitch_out;
    wire [15:0] reverb_out;
    wire [15:0] muffled_out;
    
    noise_gate ng_inst (
        .clk(clk),
        .audio_in(audio_in),
        .audio_out(noise_gate_out)
    );
    
    high_pitch_effect hp_inst (
        .clk(clk),
        .reset(reset),
        .audio_in(audio_in),
        .audio_out(high_pitch_out)
    );
    
    low_pitch_effect lp_inst (
        .clk(clk),
        .reset(reset),
        .audio_in(audio_in),
        .audio_out(low_pitch_out)
    );
    
    reverb_effect rev_inst (
        .clk(clk),
        .reset(reset),
        .audio_in(audio_in),
        .audio_out(reverb_out)
    );
    
    muffled_effect muf_inst (
        .clk(clk),
        .reset(reset),
        .audio_in(audio_in),
        .audio_out(muffled_out)
    );
    
    always @(posedge clk or posedge reset) begin
        if (reset) audio_out <= 16'd0;
        else begin
            case (effect_select)
                3'b000: audio_out <= noise_gate_out;
                3'b001: audio_out <= high_pitch_out;
                3'b010: audio_out <= low_pitch_out;
                3'b011: audio_out <= reverb_out;
                3'b100: audio_out <= muffled_out;
                default: audio_out <= audio_in;
            endcase
        end
    end
endmodule
