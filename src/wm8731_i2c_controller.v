// ============================================================================
// I2C Controller for WM8731 Audio Codec Configuration
// ============================================================================
// Handles I2C communication for configuring the Wolfson WM8731 chip
// Supports write transactions to configure codec registers
// Clock frequency: ~100kHz I2C from 50MHz system clock
// ============================================================================

module i2c_controller (
    input             clk,          // System clock (50MHz)
    input             reset,        // Active high reset
    input             start,        // Start I2C transaction (pulse)
    input      [6:0]  device_addr,  // 7-bit I2C device address
    input      [15:0] register_data, // 16-bit data to write
    output reg        ready,        // Ready for new transaction
    output reg        i2c_sclk,     // I2C clock output
    inout             i2c_sdat      // I2C bidirectional data
);

    // ========================================================================
    // I2C Timing Parameters
    // ========================================================================
    // Generate ~100kHz I2C clock from 50MHz system clock
    // 50MHz / 250 = 200kHz toggle rate = 100kHz I2C SCL
    localparam DIVIDER = 250;
    
    // ========================================================================
    // State Machine States
    // ========================================================================
    localparam IDLE       = 4'd0;   // Idle, waiting for start
    localparam START_COND = 4'd1;   // Generate START condition
    localparam ADDR_BYTE  = 4'd2;   // Send device address + R/W bit
    localparam ACK1       = 4'd3;   // Wait for ACK after address
    localparam DATA_HIGH  = 4'd4;   // Send high byte of data
    localparam ACK2       = 4'd5;   // Wait for ACK after high byte
    localparam DATA_LOW   = 4'd6;   // Send low byte of data
    localparam ACK3       = 4'd7;   // Wait for ACK after low byte
    localparam STOP_COND  = 4'd8;   // Generate STOP condition
    localparam DONE       = 4'd9;   // Transaction complete
    
    // ========================================================================
    // Internal Registers
    // ========================================================================
    reg [3:0]  state;           // State machine state
    reg [8:0]  clk_div;         // Clock divider counter
    reg [3:0]  bit_cnt;         // Bit counter for byte transmission
    reg [7:0]  addr_byte;       // Address byte buffer
    reg [7:0]  data_high_byte;  // High byte of data
    reg [7:0]  data_low_byte;   // Low byte of data
    reg        sdat_out;        // SDAT output value
    reg        sdat_oe;         // SDAT output enable (1=drive, 0=tristate)
    
    // ========================================================================
    // Bidirectional Buffer for I2C Data Line
    // ========================================================================
    // Drive SDAT when output enable is high, otherwise tristate for ACK
    assign i2c_sdat = sdat_oe ? sdat_out : 1'bz;
    
    // ========================================================================
    // Main I2C Controller State Machine
    // ========================================================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Reset all registers
            state <= IDLE;
            ready <= 1'b1;
            i2c_sclk <= 1'b1;
            sdat_out <= 1'b1;
            sdat_oe <= 1'b1;
            clk_div <= 9'd0;
            bit_cnt <= 4'd0;
        end else begin
            // Clock divider for I2C timing
            clk_div <= clk_div + 1'd1;
            
            // Execute state machine at divided clock rate
            if (clk_div == DIVIDER) begin
                clk_div <= 9'd0;
                
                case (state)
                    // --------------------------------------------------------
                    // IDLE: Wait for start signal
                    // --------------------------------------------------------
                    IDLE: begin
                        ready <= 1'b1;
                        i2c_sclk <= 1'b1;
                        sdat_out <= 1'b1;
                        sdat_oe <= 1'b1;
                        
                        if (start) begin
                            ready <= 1'b0;
                            // Prepare data bytes
                            addr_byte <= {device_addr, 1'b0};  // R/W=0 (write)
                            data_high_byte <= register_data[15:8];
                            data_low_byte <= register_data[7:0];
                            state <= START_COND;
                        end
                    end
                    
                    // --------------------------------------------------------
                    // START_COND: Generate I2C START condition
                    // SDA falls while SCL is high
                    // --------------------------------------------------------
                    START_COND: begin
                        sdat_out <= 1'b0;  // Pull SDA low
                        state <= ADDR_BYTE;
                        bit_cnt <= 4'd7;   // Start from MSB
                    end
                    
                    // --------------------------------------------------------
                    // ADDR_BYTE: Send 8-bit address + R/W
                    // --------------------------------------------------------
                    ADDR_BYTE: begin
                        i2c_sclk <= 1'b0;
                        sdat_out <= addr_byte[bit_cnt];
                        
                        if (bit_cnt == 0) begin
                            state <= ACK1;
                        end else begin
                            bit_cnt <= bit_cnt - 1'd1;
                            i2c_sclk <= 1'b1;
                        end
                    end
                    
                    // --------------------------------------------------------
                    // ACK1: Wait for acknowledgment from slave
                    // --------------------------------------------------------
                    ACK1: begin
                        i2c_sclk <= 1'b0;
                        sdat_oe <= 1'b0;    // Release SDA for slave ACK
                        i2c_sclk <= 1'b1;
                        state <= DATA_HIGH;
                        bit_cnt <= 4'd7;
                    end
                    
                    // --------------------------------------------------------
                    // DATA_HIGH: Send high byte of register data
                    // --------------------------------------------------------
                    DATA_HIGH: begin
                        i2c_sclk <= 1'b0;
                        sdat_oe <= 1'b1;    // Take control of SDA
                        sdat_out <= data_high_byte[bit_cnt];
                        
                        if (bit_cnt == 0) begin
                            state <= ACK2;
                        end else begin
                            bit_cnt <= bit_cnt - 1'd1;
                            i2c_sclk <= 1'b1;
                        end
                    end
                    
                    // --------------------------------------------------------
                    // ACK2: Wait for acknowledgment
                    // --------------------------------------------------------
                    ACK2: begin
                        i2c_sclk <= 1'b0;
                        sdat_oe <= 1'b0;    // Release SDA for slave ACK
                        i2c_sclk <= 1'b1;
                        state <= DATA_LOW;
                        bit_cnt <= 4'd7;
                    end
                    
                    // --------------------------------------------------------
                    // DATA_LOW: Send low byte of register data
                    // --------------------------------------------------------
                    DATA_LOW: begin
                        i2c_sclk <= 1'b0;
                        sdat_oe <= 1'b1;    // Take control of SDA
                        sdat_out <= data_low_byte[bit_cnt];
                        
                        if (bit_cnt == 0) begin
                            state <= ACK3;
                        end else begin
                            bit_cnt <= bit_cnt - 1'd1;
                            i2c_sclk <= 1'b1;
                        end
                    end
                    
                    // --------------------------------------------------------
                    // ACK3: Wait for final acknowledgment
                    // --------------------------------------------------------
                    ACK3: begin
                        i2c_sclk <= 1'b0;
                        sdat_oe <= 1'b0;    // Release SDA for slave ACK
                        i2c_sclk <= 1'b1;
                        state <= STOP_COND;
                    end
                    
                    // --------------------------------------------------------
                    // STOP_COND: Generate I2C STOP condition
                    // SDA rises while SCL is high
                    // --------------------------------------------------------
                    STOP_COND: begin
                        i2c_sclk <= 1'b0;
                        sdat_oe <= 1'b1;
                        sdat_out <= 1'b0;
                        i2c_sclk <= 1'b1;
                        sdat_out <= 1'b1;  // SDA rises (STOP)
                        state <= DONE;
                    end
                    
                    // --------------------------------------------------------
                    // DONE: Transaction complete
                    // --------------------------------------------------------
                    DONE: begin
                        ready <= 1'b1;
                        state <= IDLE;
                    end
                    
                    // --------------------------------------------------------
                    // Default: Return to IDLE
                    // --------------------------------------------------------
                    default: state <= IDLE;
                endcase
            end
        end
    end

endmodule
