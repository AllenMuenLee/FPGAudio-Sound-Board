// ============================================================================
// WM8731 Audio Codec Configuration Module
// ============================================================================
// Initializes the Wolfson WM8731 codec via I2C
// Configuration: Master mode, 48kHz sample rate, Line In/Out enabled
// Sends initialization sequence to configure all codec registers
// ============================================================================

module wm8731_config (
    input      clk,          // System clock (50MHz)
    input      reset,        // Active high reset
    output reg config_done,  // Configuration complete flag
    output     i2c_sclk,     // I2C clock output
    inout      i2c_sdat      // I2C data (bidirectional)
);

    // ========================================================================
    // WM8731 I2C Device Address
    // ========================================================================
    // 7-bit I2C address for WM8731 (CSB pin determines address)
    localparam WM8731_ADDR = 7'b0011010;  // 0x1A (CSB=0)
    
    // ========================================================================
    // Configuration Register Count
    // ========================================================================
    localparam NUM_REGS = 10;  // Number of registers to configure
    
    // ========================================================================
    // Internal Registers
    // ========================================================================
    reg [15:0] config_data [0:NUM_REGS-1];  // Configuration data array
    reg [3:0]  reg_index;                    // Current register index
    reg        i2c_start;                    // I2C start signal
    wire       i2c_ready;                    // I2C ready signal
    
    // ========================================================================
    // WM8731 Register Configuration Data
    // ========================================================================
    // Format: [15:9] = register address, [8:0] = register data
    initial begin
        // R15 (0x0F): Reset Register
        // Write 0x00 to reset all registers to default
        config_data[0] = 16'b0001111_000000000;
        
        // R0 (0x00): Left Line In
        // Enable input, 0dB gain, unmute
        config_data[1] = 16'b0000000_010010111;
        
        // R1 (0x01): Right Line In  
        // Enable input, 0dB gain, unmute
        config_data[2] = 16'b0000001_010010111;
        
        // R2 (0x02): Left Headphone Out
        // 0dB volume, enable zero-cross detect
        config_data[3] = 16'b0000010_001111001;
        
        // R3 (0x03): Right Headphone Out
        // 0dB volume, enable zero-cross detect
        config_data[4] = 16'b0000011_001111001;
        
        // R4 (0x04): Analog Audio Path Control
        // Select line input to ADC, bypass OFF, DAC selected
        config_data[5] = 16'b0000100_000010010;
        
        // R5 (0x05): Digital Audio Path Control
        // DAC enabled, no de-emphasis
        config_data[6] = 16'b0000101_000000000;
        
        // R6 (0x06): Power Down Control
        // Power up all sections (all bits = 0)
        config_data[7] = 16'b0000110_000000000;
        
        // R7 (0x07): Digital Audio Interface Format
        // I2S format, 16-bit, Master mode, no bit clock inversion
        config_data[8] = 16'b0000111_001000010;
        
        // R8 (0x08): Sampling Control
        // Normal mode, 48kHz sample rate (with 12.288MHz MCLK)
        // USB mode off, base oversampling rate
        config_data[9] = 16'b0001000_000000000;
    end
    
    // ========================================================================
    // State Machine States
    // ========================================================================
    localparam IDLE  = 2'd0;  // Idle state
    localparam WAIT  = 2'd1;  // Wait for I2C completion
    localparam SEND  = 2'd2;  // Send I2C command
    localparam DELAY = 2'd3;  // Delay between commands
    
    reg [1:0]  state;      // State machine state
    reg [19:0] delay_cnt;  // Delay counter (20 bits for long delays)
    
    // ========================================================================
    // I2C Controller Instance
    // ========================================================================
    // Handles low-level I2C communication
    i2c_controller i2c_ctrl (
        .clk(clk),
        .reset(reset),
        .start(i2c_start),
        .device_addr(WM8731_ADDR),
        .register_data(config_data[reg_index]),
        .ready(i2c_ready),
        .i2c_sclk(i2c_sclk),
        .i2c_sdat(i2c_sdat)
    );
    
    // ========================================================================
    // Configuration Sequencer State Machine
    // ========================================================================
    // Sends all configuration registers to WM8731 in sequence
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            reg_index <= 4'd0;
            i2c_start <= 1'b0;
            config_done <= 1'b0;
            delay_cnt <= 20'd0;
        end else begin
            case (state)
                // --------------------------------------------------------
                // IDLE: Wait for I2C controller to be ready
                // --------------------------------------------------------
                IDLE: begin
                    if (i2c_ready) begin
                        state <= DELAY;
                        delay_cnt <= 20'd50000;  // Initial delay ~1ms
                    end
                end
                
                // --------------------------------------------------------
                // DELAY: Wait specified time before next command
                // --------------------------------------------------------
                DELAY: begin
                    if (delay_cnt > 0) begin
                        delay_cnt <= delay_cnt - 1'd1;
                    end else begin
                        state <= SEND;
                    end
                end
                
                // --------------------------------------------------------
                // SEND: Pulse I2C start signal
                // --------------------------------------------------------
                SEND: begin
                    i2c_start <= 1'b1;
                    state <= WAIT;
                end
                
                // --------------------------------------------------------
                // WAIT: Wait for I2C transaction to complete
                // --------------------------------------------------------
                WAIT: begin
                    i2c_start <= 1'b0;
                    
                    if (i2c_ready) begin
                        if (reg_index < NUM_REGS - 1) begin
                            // More registers to configure
                            reg_index <= reg_index + 1'd1;
                            state <= DELAY;
                            delay_cnt <= 20'd10000;  // Inter-register delay ~200us
                        end else begin
                            // All registers configured
                            config_done <= 1'b1;
                            state <= IDLE;
                        end
                    end
                end
                
                // --------------------------------------------------------
                // Default: Return to IDLE
                // --------------------------------------------------------
                default: state <= IDLE;
            endcase
        end
    end

endmodule
