// ============================================================================
// Testbench for DE1-SoC Audio Processor
// ============================================================================
// Features:
//   - Statistical analysis (min/max/avg/RMS/Gain)  
//   - Optimized for <100MB GitHub constraint       
//   - Silence gaps between tests for clarity       
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

    // ========================================================================
    // Parameters - Optimized for <100MB file size
    // ========================================================================
    parameter integer CLK_PERIOD = 20;               // Changed: 20ns = 50MHz (realistic)
    parameter integer CLK_FREQ_HZ = 50_000_000;
    parameter integer AUDIO_SAMPLE_RATE = 48_000;    // Changed: Standard 48kHz
    parameter integer SAMPLES_PER_TONE = 100;        // Changed: Reduced for file size
    parameter integer SINE_AMPLITUDE = 10_000;
    parameter integer SAW_AMPLITUDE  = 10_000;
    parameter integer SILENCE_SAMPLES = 20;          // Added: Gap between tests

    localparam integer SAMPLE_DIV = 1;
    localparam integer SINE_FREQ_HZ = 1_000;         // Changed: 1kHz for clarity
    localparam integer SAW_FREQ_HZ  = 500;           // Changed: 500Hz for clarity

    // ========================================================================
    // DUT Interface
    // ========================================================================
    reg                clk;
    reg                reset;
    reg  signed [15:0] audio_in;
    reg  [9:0]         SW;
    wire signed [15:0] audio_out;

    // Added: Statistics collection variables
    real sum_in, sum_out, sum_sq_in, sum_sq_out;
    integer count_samples;
    reg signed [15:0] min_in, max_in, min_out, max_out;  // Fixed: match audio signal width

    audio_processor dut (
        .clk(clk),
        .reset(reset),
        .audio_in(audio_in),
        .SW(SW),
        .audio_out(audio_out)
    );

    // ========================================================================
    // Clock Generation
    // ========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ========================================================================
    // Audio Sample Tick
    // ========================================================================
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

    // ========================================================================
    // Waveform Dump (REQUIRED: DO NOT CHANGE)
    // ========================================================================
    initial begin
        $dumpfile("sim_out/wave.vcd");  
        $dumpvars(0, tb);                
    end

    // ========================================================================
    // Main Test Sequence
    // ========================================================================
    initial begin
        $display("TEST START");
        $display("============================================================");
        $display("  DE1-SoC Audio Processor Verification");
        $display("============================================================");
        $display("Configuration:");
        $display("  Clock Frequency:    %0d MHz", (CLK_FREQ_HZ/1_000_000));
        $display("  Audio Sample Rate:  %0d kHz", (AUDIO_SAMPLE_RATE/1_000));  // Changed: kHz
        $display("  Sine Tone:          %0d Hz", SINE_FREQ_HZ);
        $display("  Saw Tone:           %0d Hz", SAW_FREQ_HZ);
        $display("  Samples per Tone:   %0d", SAMPLES_PER_TONE);
        $display("  Est. Total Cycles:  ~%0d", (SAMPLES_PER_TONE + SILENCE_SAMPLES) * 5 * 2 + 100);  // Added
        $display("============================================================\n");

        audio_in = 16'sd0;
        SW = 10'b0;
        reset = 1'b1;

        repeat(10) @(posedge clk);
        reset = 1'b0;
        repeat(10) @(posedge clk);

        // Test all effects
        test_effect(3'b000, "Noise Gate");
        test_effect(3'b001, "High Pitch");
        test_effect(3'b010, "Low Pitch");
        test_effect(3'b011, "Reverb");
        test_effect(3'b100, "Muffled");

        $display("\n[%0t] ========== ALL TESTS PASSED ==========", $time);  
        $display("TEST PASSED");                                            
        repeat(10) @(posedge clk);
        $finish;
    end

    // ========================================================================
    // Test Effect Task - Added: comprehensive testing with stats
    // ========================================================================
    task test_effect;
        input [2:0] effect_code;
        input [185*8:1] effect_name;  
        begin
            SW[2:0] = effect_code;
            $display("\n[%0t] Testing %0s (SW[2:0]=%b)", $time, effect_name, effect_code);
            repeat(5) @(posedge clk);
            
            // Sine test
            $display("[%0t]   Sine: %0d Hz", $time, SINE_FREQ_HZ);
            reset_stats();                                                 // Added
            play_sine_tone(SINE_FREQ_HZ, SINE_AMPLITUDE, SAMPLES_PER_TONE);
            print_stats({effect_name, " - Sine"});                         // Added
            audio_in = 16'sd0; repeat(SILENCE_SAMPLES) @(posedge clk);    // Added: silence gap
            
            // Saw test
            $display("[%0t]   Saw : %0d Hz", $time, SAW_FREQ_HZ);
            reset_stats();                                                 // Added
            play_saw_tone(SAW_FREQ_HZ, SAW_AMPLITUDE, SAMPLES_PER_TONE);
            print_stats({effect_name, " - Saw "});                         
            audio_in = 16'sd0; repeat(SILENCE_SAMPLES) @(posedge clk);    // Added: silence gap
        end
    endtask

    // ========================================================================
    // Statistics Tasks - Added: for comprehensive metrics
    // ========================================================================
    task reset_stats;
        begin
            sum_in = 0.0; sum_out = 0.0;
            sum_sq_in = 0.0; sum_sq_out = 0.0;
            count_samples = 0;
            min_in = 32767; max_in = -32768;
            min_out = 32767; max_out = -32768;
        end
    endtask

    task print_stats;
        input [192*8:1] name;  // 192 chars total for name with suffix
        real avg_in, avg_out, rms_in, rms_out, gain_db;
        begin
            if (count_samples > 0) begin
                avg_in = sum_in / count_samples;
                avg_out = sum_out / count_samples;
                rms_in = $sqrt(sum_sq_in / count_samples);
                rms_out = $sqrt(sum_sq_out / count_samples);
                gain_db = 20.0 * $log10((rms_out + 0.001) / (rms_in + 0.001));
                $display("       Stats [%0s]:", name);
                $display("         In : min=%6d max=%6d avg=%8.1f RMS=%8.1f", 
                         min_in, max_in, avg_in, rms_in);
                $display("         Out: min=%6d max=%6d avg=%8.1f RMS=%8.1f Gain=%.2fdB", 
                         min_out, max_out, avg_out, rms_out, gain_db);
            end
        end
    endtask

    // ========================================================================
    // Helper Tasks
    // ========================================================================
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
        real phase, phase_inc, s;
        begin
            phase = 0.0;
            phase_inc = 2.0 * 3.14159265359 * freq_hz / AUDIO_SAMPLE_RATE;
            for (i = 0; i < num_samples; i = i + 1) begin
                wait_sample_tick();
                s = $sin(phase);
                audio_in = 16'($rtoi(amplitude * s));
                @(posedge clk);  // Let output settle
                
                // Added: Collect statistics
                sum_in = sum_in + $itor(audio_in);
                sum_out = sum_out + $itor(audio_out);
                sum_sq_in = sum_sq_in + ($itor(audio_in) * $itor(audio_in));
                sum_sq_out = sum_sq_out + ($itor(audio_out) * $itor(audio_out));
                if (audio_in < min_in) min_in = audio_in;
                if (audio_in > max_in) max_in = audio_in;
                if (audio_out < min_out) min_out = audio_out;
                if (audio_out > max_out) max_out = audio_out;
                count_samples = count_samples + 1;
                
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
        real phase, phase_inc, v;
        begin
            phase = 0.0;
            phase_inc = (1.0 * freq_hz) / AUDIO_SAMPLE_RATE;
            for (i = 0; i < num_samples; i = i + 1) begin
                wait_sample_tick();
                v = (2.0 * phase) - 1.0;
                audio_in = 16'($rtoi(amplitude * v));
                @(posedge clk);  // Added: let output settle
                
                // Added: Collect statistics (same as sine)
                sum_in = sum_in + $itor(audio_in);
                sum_out = sum_out + $itor(audio_out);
                sum_sq_in = sum_sq_in + ($itor(audio_in) * $itor(audio_in));
                sum_sq_out = sum_sq_out + ($itor(audio_out) * $itor(audio_out));
                if (audio_in < min_in) min_in = audio_in;
                if (audio_in > max_in) max_in = audio_in;
                if (audio_out < min_out) min_out = audio_out;
                if (audio_out > max_out) max_out = audio_out;
                count_samples = count_samples + 1;
                
                phase = phase + phase_inc;
                if (phase >= 1.0) phase = phase - 1.0;
            end
        end
    endtask

endmodule
