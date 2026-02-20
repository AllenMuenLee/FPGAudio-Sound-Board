// ============================================================================
// COMPLETE AUDIO SYSTEM FOR DE1-SOC - ALL MODULES IN ONE FILE
// ============================================================================

// MODULE 1: I2C Controller
module i2c_controller (
    input clk, input reset, input start, input [6:0] device_addr, input [15:0] register_data,
    output reg ready, output reg i2c_sclk, inout i2c_sdat
);
    localparam DIVIDER=250, IDLE=0, START_COND=1, ADDR_BYTE=2, ACK1=3, DATA_HIGH=4, ACK2=5, DATA_LOW=6, ACK3=7, STOP_COND=8, DONE=9;
    reg [3:0] state; reg [8:0] clk_div; reg [3:0] bit_cnt; reg [7:0] addr_byte, data_high_byte, data_low_byte;
    reg sdat_out, sdat_oe; assign i2c_sdat = sdat_oe ? sdat_out : 1'bz;
    always @(posedge clk or posedge reset) begin
        if (reset) begin state<=IDLE; ready<=1; i2c_sclk<=1; sdat_out<=1; sdat_oe<=1; clk_div<=0; bit_cnt<=0;
        end else begin clk_div <= clk_div + 1; if (clk_div == DIVIDER) begin clk_div <= 0;
            case (state)
                IDLE: begin ready<=1; i2c_sclk<=1; sdat_out<=1; sdat_oe<=1;
                    if (start) begin ready<=0; addr_byte<={device_addr,1'b0}; data_high_byte<=register_data[15:8];
                    data_low_byte<=register_data[7:0]; state<=START_COND; end end
                START_COND: begin sdat_out<=0; state<=ADDR_BYTE; bit_cnt<=7; end
                ADDR_BYTE: begin i2c_sclk<=0; sdat_out<=addr_byte[bit_cnt];
                    if (bit_cnt==0) state<=ACK1; else begin bit_cnt<=bit_cnt-1; i2c_sclk<=1; end end
                ACK1: begin i2c_sclk<=0; sdat_oe<=0; i2c_sclk<=1; state<=DATA_HIGH; bit_cnt<=7; end
                DATA_HIGH: begin i2c_sclk<=0; sdat_oe<=1; sdat_out<=data_high_byte[bit_cnt];
                    if (bit_cnt==0) state<=ACK2; else begin bit_cnt<=bit_cnt-1; i2c_sclk<=1; end end
                ACK2: begin i2c_sclk<=0; sdat_oe<=0; i2c_sclk<=1; state<=DATA_LOW; bit_cnt<=7; end
                DATA_LOW: begin i2c_sclk<=0; sdat_oe<=1; sdat_out<=data_low_byte[bit_cnt];
                    if (bit_cnt==0) state<=ACK3; else begin bit_cnt<=bit_cnt-1; i2c_sclk<=1; end end
                ACK3: begin i2c_sclk<=0; sdat_oe<=0; i2c_sclk<=1; state<=STOP_COND; end
                STOP_COND: begin i2c_sclk<=0; sdat_oe<=1; sdat_out<=0; i2c_sclk<=1; sdat_out<=1; state<=DONE; end
                DONE: begin ready<=1; state<=IDLE; end
                default: state<=IDLE;
            endcase
        end end
    end
endmodule

// MODULE 2: WM8731 Configuration
module wm8731_config (input clk, input reset, output reg config_done, output i2c_sclk, inout i2c_sdat);
    localparam WM8731_ADDR=7'b0011010, NUM_REGS=10;
    reg [15:0] config_data [0:NUM_REGS-1]; reg [3:0] reg_index; reg i2c_start; wire i2c_ready;
    initial begin
        config_data[0]=16'b0001111_000000000; config_data[1]=16'b0000000_010010111;
        config_data[2]=16'b0000001_010010111; config_data[3]=16'b0000010_001111001;
        config_data[4]=16'b0000011_001111001; config_data[5]=16'b0000100_000010010;
        config_data[6]=16'b0000101_000000000; config_data[7]=16'b0000110_000000000;
        config_data[8]=16'b0000111_001000010; config_data[9]=16'b0001000_000000000;
    end
    localparam IDLE=0, WAIT=1, SEND=2, DELAY=3;
    reg [1:0] state; reg [19:0] delay_cnt;
    i2c_controller i2c_ctrl (.clk(clk), .reset(reset), .start(i2c_start), .device_addr(WM8731_ADDR),
        .register_data(config_data[reg_index]), .ready(i2c_ready), .i2c_sclk(i2c_sclk), .i2c_sdat(i2c_sdat));
    always @(posedge clk or posedge reset) begin
        if (reset) begin state<=IDLE; reg_index<=0; i2c_start<=0; config_done<=0; delay_cnt<=0;
        end else begin
            case (state)
                IDLE: if (i2c_ready) begin state<=DELAY; delay_cnt<=50000; end
                DELAY: if (delay_cnt>0) delay_cnt<=delay_cnt-1; else state<=SEND;
                SEND: begin i2c_start<=1; state<=WAIT; end
                WAIT: begin i2c_start<=0; if (i2c_ready) begin
                    if (reg_index<NUM_REGS-1) begin reg_index<=reg_index+1; state<=DELAY; delay_cnt<=10000;
                    end else begin config_done<=1; state<=IDLE; end end end
                default: state<=IDLE;
            endcase
        end
    end
endmodule

// MODULE 3: I2S Interface
module i2s_interface (
    input clk, input reset, input aud_adclrck, input aud_bclk, input aud_adcdat, output reg aud_dacdat,
    input [15:0] audio_out_l, input [15:0] audio_out_r, output reg [15:0] audio_in_l, output reg [15:0] audio_in_r,
    output reg audio_valid
);
    reg [2:0] bclk_sync, lrck_sync;
    always @(posedge clk or posedge reset) begin
        if (reset) begin bclk_sync<=0; lrck_sync<=0;
        end else begin bclk_sync<={bclk_sync[1:0],aud_bclk}; lrck_sync<={lrck_sync[1:0],aud_adclrck}; end
    end
    wire bclk_rising=(bclk_sync[2:1]==2'b01), bclk_falling=(bclk_sync[2:1]==2'b10);
    wire lrck_edge=(lrck_sync[2:1]!=2'b00)&&(lrck_sync[2:1]!=2'b11), left_channel=~lrck_sync[2];
    reg [15:0] adc_shift_reg, dac_shift_reg; reg [4:0] bit_cnt; reg [15:0] adc_left_temp, adc_right_temp;
    always @(posedge clk or posedge reset) begin
        if (reset) begin adc_shift_reg<=0; dac_shift_reg<=0; bit_cnt<=0; audio_in_l<=0; audio_in_r<=0;
            aud_dacdat<=0; audio_valid<=0; adc_left_temp<=0; adc_right_temp<=0;
        end else begin audio_valid<=0;
            if (lrck_edge) begin bit_cnt<=15;
                if (left_channel) begin dac_shift_reg<=audio_out_l; audio_in_r<=adc_shift_reg; audio_valid<=1;
                end else begin dac_shift_reg<=audio_out_r; audio_in_l<=adc_shift_reg; end
            end
            else if (bclk_falling && bit_cnt<16) begin aud_dacdat<=dac_shift_reg[15];
                dac_shift_reg<={dac_shift_reg[14:0],1'b0}; bit_cnt<=bit_cnt-1; end
            else if (bclk_rising && bit_cnt<16) adc_shift_reg<={adc_shift_reg[14:0],aud_adcdat};
        end
    end
endmodule

// MODULE 4: Audio Clock
module audio_clock (input clk_50mhz, input reset, output reg aud_xck);
    reg [2:0] counter;
    always @(posedge clk_50mhz or posedge reset) begin
        if (reset) begin counter<=0; aud_xck<=0;
        end else begin
            if (counter>=1) begin counter<=0; aud_xck<=~aud_xck;
            end else counter<=counter+1;
        end
    end
endmodule

// MODULE 5: VU Meter
module vu_meter (input clk, input reset, input [15:0] audio_sample, output reg [9:0] led_out);
    wire [15:0] abs_sample; assign abs_sample = audio_sample[15] ? (~audio_sample + 1'b1) : audio_sample;
    wire [3:0] current_level; assign current_level = abs_sample[15:12];
    reg [3:0] peak_level; reg [23:0] decay_counter;
    localparam DECAY_TIME = 24'd16_777_216;
    always @(posedge clk or posedge reset) begin
        if (reset) begin peak_level<=4'd0; decay_counter<=24'd0; led_out<=10'd0;
        end else begin
            if (current_level > peak_level) begin peak_level<=current_level; decay_counter<=DECAY_TIME;
            end else if (decay_counter>0) decay_counter<=decay_counter-1'b1;
            else begin if (peak_level>0) peak_level<=peak_level-1'b1; decay_counter<=DECAY_TIME; end
            case (peak_level)
                4'd0: led_out<=10'b0000000000; 4'd1: led_out<=10'b0000000001; 4'd2: led_out<=10'b0000000011;
                4'd3: led_out<=10'b0000000111; 4'd4: led_out<=10'b0000001111; 4'd5: led_out<=10'b0000011111;
                4'd6: led_out<=10'b0000111111; 4'd7: led_out<=10'b0001111111; 4'd8: led_out<=10'b0011111111;
                4'd9: led_out<=10'b0111111111; default: led_out<=10'b1111111111;
            endcase
        end
    end
endmodule
