// ============================================================================
// Testbench for DE1-SoC Audio Processor
// ============================================================================
// Description:
//   Comprehensive testbench for audio_processor module.
//
// Features:
//   - Generates synthesized audio waveforms (sine wave approximation)
//   - Tests all 5 audio effects with real stimulus
//   - Detailed console logging for headless CI/CD environments
//   - VCD waveform dumping for post-simulation analysis
//
// Effect Coverage:
//   SW[2:0] = 3'b000 : Noise Gate
//   SW[2:0] = 3'b001 : High Pitch
//   SW[2:0] = 3'b010 : Low Pitch
//   SW[2:0] = 3'b011 : Reverb
//   SW[2:0] = 3'b100 : Muffled
// ============================================================================

`timescale 1ns / 1ps

module tb;

    // ------------------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------------------
    parameter integer CLK_PERIOD = 20;          // 50MHz
    parameter integer CLK_FREQ_HZ = 50_000_000;
    parameter integer AUDIO_SAMPLE_RATE = 48_000;
    parameter integer SAMPLES_PER_TONE = 48;    // Keep small for VCD size
    parameter integer SINE_AMPLITUDE = 16_000;
    parameter integer SAW_AMPLITUDE  = 16_000;

    localparam integer SAMPLE_DIV = (CLK_FREQ_HZ + (AUDIO_SAMPLE_RATE/2)) / AUDIO_SAMPLE_RATE;

    localparam integer NUM_TONES = 1;

    // ------------------------------------------------------------------------
    // DUT interface
    // ------------------------------------------------------------------------
    reg                clk;
    reg                reset;
    reg  signed [15:0] audio_in;
    reg  [9:0]         SW;
    wire signed [15:0] audio_out;

    audio_processor dut (
        .clk(clk),
        .reset(reset),
        .audio_in(audio_in),
        .SW(SW),
        .audio_out(audio_out)
    );

    // ------------------------------------------------------------------------
    // Clock generation
    // ------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ------------------------------------------------------------------------
    // Audio sample tick (48kHz-equivalent)
    // ------------------------------------------------------------------------
    integer sample_cnt;
    reg sample_tick;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sample_cnt <= 0;
            sample_tick <= 1'b0;
        end else begin
            if (sample_cnt == SAMPLE_DIV - 1) begin
                sample_cnt <= 0;
                sample_tick <= 1'b1;
            end else begin
                sample_cnt <= sample_cnt + 1;
                sample_tick <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Waveform dump (full TB scope)
    // ------------------------------------------------------------------------
    initial begin
        $dumpfile("sim_out/wave.vcd");
        $dumpvars(0, tb);
    end

    // ------------------------------------------------------------------------
    // Tone lists
    // ------------------------------------------------------------------------
    integer sine_freqs [0:NUM_TONES-1];
    integer saw_freqs  [0:NUM_TONES-1];

    initial begin
        sine_freqs[0] = 1000;
        saw_freqs[0]  = 1000;
    end

    // ------------------------------------------------------------------------
    // Main test sequence
    // ------------------------------------------------------------------------
    integer tone_idx;

    initial begin
        $display("TEST START");
        $display("============================================================");
        $display("  DE1-SoC Audio Processor Verification");
        $display("  CI/CD Automated Testing Suite");
        $display("============================================================");
        $display("Configuration:");
        $display("  Clock Frequency:    %0d MHz", (CLK_FREQ_HZ/1_000_000));
        $display("  Audio Sample Rate:  %0d Hz", AUDIO_SAMPLE_RATE);
        $display("  Sine/Saw Tones:     %0d each per effect", NUM_TONES);
        $display("  Samples per Tone:   %0d", SAMPLES_PER_TONE);
        $display("============================================================\n");

        audio_in = 16'sd0;
        SW = 10'b0;
        reset = 1'b1;

        repeat(10) @(posedge clk);
        reset = 1'b0;
        repeat(10) @(posedge clk);

        // ------------------------------------------------------------
        // Effect 0: Noise Gate (SW[2:0] = 000)
        // ------------------------------------------------------------
        SW[2:0] = 3'b000;
        $display("[%0t] Testing Effect 0 (Noise Gate) SW=%b", $time, SW[2:0]);
        repeat(5) @(posedge clk);
        $display("[%0t]   Sine: %0d Hz", $time, sine_freqs[0]);
        play_sine_tone(sine_freqs[0], SINE_AMPLITUDE, SAMPLES_PER_TONE);
        $display("[%0t]   Saw : %0d Hz", $time, saw_freqs[0]);
        play_saw_tone(saw_freqs[0], SAW_AMPLITUDE, SAMPLES_PER_TONE);

        // ------------------------------------------------------------
        // Effect 1: High Pitch (SW[2:0] = 001)
        // ------------------------------------------------------------
        SW[2:0] = 3'b001;
        $display("[%0t] Testing Effect 1 (High Pitch) SW=%b", $time, SW[2:0]);
        repeat(5) @(posedge clk);
        $display("[%0t]   Sine: %0d Hz", $time, sine_freqs[0]);
        play_sine_tone(sine_freqs[0], SINE_AMPLITUDE, SAMPLES_PER_TONE);
        $display("[%0t]   Saw : %0d Hz", $time, saw_freqs[0]);
        play_saw_tone(saw_freqs[0], SAW_AMPLITUDE, SAMPLES_PER_TONE);

        // ------------------------------------------------------------
        // Effect 2: Low Pitch (SW[2:0] = 010)
        // ------------------------------------------------------------
        SW[2:0] = 3'b010;
        $display("[%0t] Testing Effect 2 (Low Pitch) SW=%b", $time, SW[2:0]);
        repeat(5) @(posedge clk);
        $display("[%0t]   Sine: %0d Hz", $time, sine_freqs[0]);
        play_sine_tone(sine_freqs[0], SINE_AMPLITUDE, SAMPLES_PER_TONE);
        $display("[%0t]   Saw : %0d Hz", $time, saw_freqs[0]);
        play_saw_tone(saw_freqs[0], SAW_AMPLITUDE, SAMPLES_PER_TONE);

        // ------------------------------------------------------------
        // Effect 3: Reverb (SW[2:0] = 011)
        // ------------------------------------------------------------
        SW[2:0] = 3'b011;
        $display("[%0t] Testing Effect 3 (Reverb) SW=%b", $time, SW[2:0]);
        repeat(5) @(posedge clk);
        $display("[%0t]   Sine: %0d Hz", $time, sine_freqs[0]);
        play_sine_tone(sine_freqs[0], SINE_AMPLITUDE, SAMPLES_PER_TONE);
        $display("[%0t]   Saw : %0d Hz", $time, saw_freqs[0]);
        play_saw_tone(saw_freqs[0], SAW_AMPLITUDE, SAMPLES_PER_TONE);

        // ------------------------------------------------------------
        // Effect 4: Muffled (SW[2:0] = 100)
        // ------------------------------------------------------------
        SW[2:0] = 3'b100;
        $display("[%0t] Testing Effect 4 (Muffled) SW=%b", $time, SW[2:0]);
        repeat(5) @(posedge clk);
        $display("[%0t]   Sine: %0d Hz", $time, sine_freqs[0]);
        play_sine_tone(sine_freqs[0], SINE_AMPLITUDE, SAMPLES_PER_TONE);
        $display("[%0t]   Saw : %0d Hz", $time, saw_freqs[0]);
        play_saw_tone(saw_freqs[0], SAW_AMPLITUDE, SAMPLES_PER_TONE);

        $display("\n[%0t] Simulation complete. Exiting...", $time);
        repeat(10) @(posedge clk);
        $finish;
    end

    // ------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------
    task wait_sample_tick;
        begin
            do @(posedge clk);
            while (!sample_tick);
        end
    endtask

    task play_sine_tone;
        input integer freq_hz;
        input integer amplitude;
        input integer num_samples;
        integer i;
        real phase;
        real phase_inc;
        real s;
        begin
            phase = 0.0;
            phase_inc = 2.0 * 3.14159265359 * freq_hz / AUDIO_SAMPLE_RATE;
            for (i = 0; i < num_samples; i = i + 1) begin
                wait_sample_tick();
                s = $sin(phase);
                audio_in = 16'($rtoi(amplitude * s));
                phase = phase + phase_inc;
                if (phase > 6.28318530718) phase = phase - 6.28318530718;
            end
        end
    endtask

    task play_saw_tone;
        input integer freq_hz;
        input integer amplitude;
        input integer num_samples;
        integer i;
        real phase;
        real phase_inc;
        real v;
        begin
            phase = 0.0;
            phase_inc = (1.0 * freq_hz) / AUDIO_SAMPLE_RATE;
            for (i = 0; i < num_samples; i = i + 1) begin
                wait_sample_tick();
                v = (2.0 * phase) - 1.0; // -1..+1
                audio_in = 16'($rtoi(amplitude * v));
                phase = phase + phase_inc;
                if (phase >= 1.0) phase = phase - 1.0;
            end
        end
    endtask

endmodule
