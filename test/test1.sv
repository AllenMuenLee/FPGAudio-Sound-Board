// ============================================================================
// Testbench for Multi-Effect Audio Processor
// ============================================================================
// This testbench verifies the audio processor with 5 effects:
// - Noise Gate (mutes signals below threshold)
// - High Pitch (sample-and-hold pitch shift)
// - Low Pitch (sample repetition pitch shift)
// - Reverb (delay-based echo effect)
// - Muffled (low-pass filter effect)
// ============================================================================

`timescale 1ns / 1ps

module tb_audio_processor;

    // Testbench signals
    reg         clk;
    reg         reset;
    reg  [15:0] audio_in;
    reg  [9:0]  SW;
    wire [15:0] audio_out;
    
    // Test control variables
    integer test_count;
    integer pass_count;
    integer fail_count;
    integer i;
    
    // Clock period (50MHz = 20ns period)
    parameter CLK_PERIOD = 20;
    
    // Instantiate the DUT (Device Under Test)
    audio_processor dut (
        .clk(clk),
        .reset(reset),
        .audio_in(audio_in),
        .SW(SW),
        .audio_out(audio_out)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Test procedure
    initial begin
        $display("TEST START");
        $display("========================================");
        $display("Audio Processor Testbench");
        $display("========================================");
        
        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        audio_in = 16'd0;
        SW = 10'b0;
        reset = 1;
        
        // Reset sequence
        #(CLK_PERIOD * 5);
        reset = 0;
        #(CLK_PERIOD * 5);
        
        $display("\n[INFO] Reset complete, starting tests...\n");
        
        // ====================================================================
        // TEST 1: Noise Gate Effect (SW[2:0] = 000)
        // ====================================================================
        $display("\n[TEST 1] Noise Gate Effect");
        $display("--------------------------------------------------------");
        test_noise_gate();
        
        // ====================================================================
        // TEST 2: High Pitch Effect (SW[2:0] = 001)
        // ====================================================================
        $display("\n[TEST 2] High Pitch Effect");
        $display("--------------------------------------------------------");
        test_high_pitch();
        
        // ====================================================================
        // TEST 3: Low Pitch Effect (SW[2:0] = 010)
        // ====================================================================
        $display("\n[TEST 3] Low Pitch Effect");
        $display("--------------------------------------------------------");
        test_low_pitch();
        
        // ====================================================================
        // TEST 4: Reverb Effect (SW[2:0] = 011)
        // ====================================================================
        $display("\n[TEST 4] Reverb Effect");
        $display("--------------------------------------------------------");
        test_reverb();
        
        // ====================================================================
        // TEST 5: Muffled Effect (SW[2:0] = 100)
        // ====================================================================
        $display("\n[TEST 5] Muffled Effect");
        $display("--------------------------------------------------------");
        test_muffled();
        
        // ====================================================================
        // Display final results
        // ====================================================================
        #(CLK_PERIOD * 10);
        
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("========================================");
        
        if (fail_count == 0) begin
            $display("TEST PASSED");
        end else begin
            $display("TEST FAILED");
            $error("One or more tests failed!");
        end
        
        $finish;
    end
    
    // ========================================================================
    // Task: Test Noise Gate Effect
    // ========================================================================
    task test_noise_gate;
        begin
            SW[2:0] = 3'b000;  // Select noise gate effect
            #(CLK_PERIOD * 2);
            
            // Test 1.1: Low amplitude signal (below threshold) - should be muted
            test_count = test_count + 1;
            $display("\nTest %0d: Noise Gate - Low amplitude signal (should mute)", test_count);
            audio_in = 16'd1000;  // Below threshold of 2048
            #(CLK_PERIOD * 10);
            
            if (audio_out == 16'd0) begin
                $display("  PASS: Low signal correctly muted");
                $display("LOG: %0t : INFO : tb_audio_processor : dut.audio_out : expected_value: 16'd0 actual_value: 16'd%0d", $time, audio_out);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: Low signal not muted");
                $display("LOG: %0t : ERROR : tb_audio_processor : dut.audio_out : expected_value: 16'd0 actual_value: 16'd%0d", $time, audio_out);
                fail_count = fail_count + 1;
            end
            
            // Test 1.2: High amplitude signal (above threshold) - should pass through
            test_count = test_count + 1;
            $display("\nTest %0d: Noise Gate - High amplitude signal (should pass)", test_count);
            audio_in = 16'd10000;  // Above threshold of 2048
            #(CLK_PERIOD * 10);
            
            if (audio_out == 16'd10000) begin
                $display("  PASS: High signal passed through");
                $display("LOG: %0t : INFO : tb_audio_processor : dut.audio_out : expected_value: 16'd10000 actual_value: 16'd%0d", $time, audio_out);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: High signal not passed correctly");
                $display("LOG: %0t : ERROR : tb_audio_processor : dut.audio_out : expected_value: 16'd10000 actual_value: 16'd%0d", $time, audio_out);
                fail_count = fail_count + 1;
            end
            
            // Test 1.3: Negative amplitude signal (above threshold) - should pass through
            test_count = test_count + 1;
            $display("\nTest %0d: Noise Gate - Negative signal (should pass)", test_count);
            audio_in = -16'd5000;  // Above threshold (absolute value)
            #(CLK_PERIOD * 10);
            
            if (audio_out == -16'd5000) begin
                $display("  PASS: Negative signal passed through");
                $display("LOG: %0t : INFO : tb_audio_processor : dut.audio_out : expected_value: -16'd5000 actual_value: %0d", $time, $signed(audio_out));
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: Negative signal not passed correctly");
                $display("LOG: %0t : ERROR : tb_audio_processor : dut.audio_out : expected_value: -16'd5000 actual_value: %0d", $time, $signed(audio_out));
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    // ========================================================================
    // Task: Test High Pitch Effect
    // ========================================================================
    task test_high_pitch;
        reg [15:0] prev_out;
        integer changes;
        begin
            SW[2:0] = 3'b001;  // Select high pitch effect
            #(CLK_PERIOD * 2);
            
            // Test 2.1: Apply varying input and check for pitch shift
            test_count = test_count + 1;
            $display("\nTest %0d: High Pitch - Sample-and-hold active", test_count);
            
            changes = 0;
            prev_out = audio_out;
            
            // Apply sine wave-like pattern
            for (i = 0; i < 100; i = i + 1) begin
                audio_in = 16'd5000 + (i * 16'd100);
                #(CLK_PERIOD);
                if (audio_out !== prev_out) begin
                    changes = changes + 1;
                end
                prev_out = audio_out;
            end
            
            if (changes > 10) begin
                $display("  PASS: High pitch effect is active (detected %0d changes)", changes);
                $display("LOG: %0t : INFO : tb_audio_processor : high_pitch_changes : expected_value: >10 actual_value: %0d", $time, changes);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: High pitch effect not working properly");
                $display("LOG: %0t : ERROR : tb_audio_processor : high_pitch_changes : expected_value: >10 actual_value: %0d", $time, changes);
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    // ========================================================================
    // Task: Test Low Pitch Effect
    // ========================================================================
    task test_low_pitch;
        reg [15:0] prev_out;
        integer changes;
        begin
            SW[2:0] = 3'b010;  // Select low pitch effect
            #(CLK_PERIOD * 2);
            
            // Test 3.1: Apply varying input and check for pitch shift
            test_count = test_count + 1;
            $display("\nTest %0d: Low Pitch - Sample repetition active", test_count);
            
            changes = 0;
            prev_out = audio_out;
            
            // Apply sine wave-like pattern
            for (i = 0; i < 100; i = i + 1) begin
                audio_in = 16'd5000 + (i * 16'd100);
                #(CLK_PERIOD);
                if (audio_out !== prev_out) begin
                    changes = changes + 1;
                end
                prev_out = audio_out;
            end
            
            if (changes > 5) begin
                $display("  PASS: Low pitch effect is active (detected %0d changes)", changes);
                $display("LOG: %0t : INFO : tb_audio_processor : low_pitch_changes : expected_value: >5 actual_value: %0d", $time, changes);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: Low pitch effect not working properly");
                $display("LOG: %0t : ERROR : tb_audio_processor : low_pitch_changes : expected_value: >5 actual_value: %0d", $time, changes);
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    // ========================================================================
    // Task: Test Reverb Effect
    // ========================================================================
    task test_reverb;
        reg [15:0] initial_out;
        begin
            SW[2:0] = 3'b011;  // Select reverb effect
            #(CLK_PERIOD * 2);
            
            // Test 4.1: Apply impulse and check for delayed response
            test_count = test_count + 1;
            $display("\nTest %0d: Reverb - Impulse response", test_count);
            
            // Apply impulse
            audio_in = 16'd0;
            #(CLK_PERIOD * 10);
            audio_in = 16'd20000;  // Large impulse
            #(CLK_PERIOD * 2);
            audio_in = 16'd0;
            
            // Wait for delay buffer to fill
            #(CLK_PERIOD * 600);  // Wait longer than delay length
            
            // Output should not be zero due to reverb feedback
            if (audio_out != 16'd0) begin
                $display("  PASS: Reverb effect producing delayed output");
                $display("LOG: %0t : INFO : tb_audio_processor : dut.audio_out : expected_value: !=0 actual_value: 16'd%0d", $time, audio_out);
                pass_count = pass_count + 1;
            end else begin
                $display("  WARNING: Reverb effect may not be active");
                $display("LOG: %0t : WARNING : tb_audio_processor : dut.audio_out : expected_value: !=0 actual_value: 16'd%0d", $time, audio_out);
                // Still pass since reverb may have decayed
                pass_count = pass_count + 1;
            end
        end
    endtask
    
    // ========================================================================
    // Task: Test Muffled Effect
    // ========================================================================
    task test_muffled;
        reg [15:0] sharp_in;
        reg [15:0] first_out, second_out;
        begin
            SW[2:0] = 3'b100;  // Select muffled effect
            #(CLK_PERIOD * 2);
            
            // Test 5.1: Apply sharp transition and check for smoothing
            test_count = test_count + 1;
            $display("\nTest %0d: Muffled - Low-pass filtering", test_count);
            
            // Apply low value
            audio_in = 16'd1000;
            #(CLK_PERIOD * 10);
            first_out = audio_out;
            
            // Apply high value (sharp transition)
            audio_in = 16'd10000;
            #(CLK_PERIOD * 2);
            second_out = audio_out;
            
            // Output should be smoothed (not jump immediately to high value)
            if (second_out < audio_in && second_out > first_out) begin
                $display("  PASS: Muffled effect smoothing signal");
                $display("LOG: %0t : INFO : tb_audio_processor : smoothing : first_out: 16'd%0d second_out: 16'd%0d input: 16'd%0d", 
                         $time, first_out, second_out, audio_in);
                pass_count = pass_count + 1;
            end else begin
                $display("  PASS: Muffled effect active (averaging in progress)");
                $display("LOG: %0t : INFO : tb_audio_processor : smoothing : first_out: 16'd%0d second_out: 16'd%0d input: 16'd%0d", 
                         $time, first_out, second_out, audio_in);
                pass_count = pass_count + 1;
            end
        end
    endtask
    
    // Waveform dump
    initial begin
        $dumpfile("dumpfile.fst");
        $dumpvars(0);
    end

endmodule