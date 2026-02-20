# DE1-SoC Audio Effects Processor

Real-time stereo audio effects for the DE1-SoC board using the WM8731 codec. The design processes both channels in parallel and lets you select one of five effects with the slide switches. A self-checking SystemVerilog testbench and GitHub Actions flow generate waveforms and logs on every push.

**Effects**
1. Noise Gate
2. High Pitch (chipmunk)
3. Low Pitch (deep voice)
4. Reverb
5. Muffled (low-pass)

**Effect Select (SW[2:0])**
1. `000` Noise Gate
2. `001` High Pitch
3. `010` Low Pitch
4. `011` Reverb
5. `100` Muffled

**Top-Level Modules**
1. `src/de1soc_top.sv`: `de1soc_wrapper` for DE1-SoC pinout
2. `src/audioprocessor_top.sv`: `de1soc_audio_top` system integration and `audio_processor` effect mux

**Key Source Files**
1. `src/effect_noisegate.v`
2. `src/effect_highpitch.v`
3. `src/effect_lowpitch.v`
4. `src/effect_reverb.v`
5. `src/effect_muffled.v`
6. `src/util_audioclock.v`
7. `src/util_vumeter.v`
8. `src/wm8731_i2s_interface.v`
9. `src/wm8731_config.v`
10. `src/wm8731_i2c_controller.v`

**Testbench**
1. `test/tb.sv`
2. Generates sine, impulse, and sawtooth stimulus
3. Produces `sim_out/wave.vcd` during simulation

**CI Simulation (GitHub Actions)**
1. On push/PR, runs Verilator on all files in `src/` plus `test/tb.sv`
2. Saves outputs to `.github/outputs/`:
3. `sim.log`
4. `wave.vcd`
5. `wave.svg`
6. `wave.json`

**Local Simulation (Verilator)**
```bash
verilator -sv $(find src -name '*.v') $(find src -name '*.sv') test/tb.sv \
  --top-module tb \
  --binary \
  --trace \
  --timing \
  --assert \
  -Mdir sim_out
./sim_out/Vtb | tee sim.log
```

**Hardware Usage**
1. Connect the DE1-SoC audio line-in/line-out to the WM8731 codec.
2. Use `KEY[0]` for reset (active-low on the board, inverted internally).
3. Set `SW[2:0]` to select the effect.
4. `LEDR[9:0]` displays a VU meter of the processed left channel.

**Repository Structure**
```text
src/            Design source (.v/.sv)
test/           Testbench (tb.sv)
assets/         README images
.github/        CI workflows and outputs
README.md
```

**DE1-SoC Physical Interface**
```mermaid
graph LR
    %% External Inputs & Outputs
    subgraph DE1-SoC Physical Interfaces
        SW[Switches SW 2:0]
        LED[VU Meter LEDs LEDR 9:0]
        MIC[Audio Line-In]
        SPK[Audio Line-Out]
    end

    %% Audio Codec Chip
    subgraph WM8731 Audio Codec
        ADC[Analog to Digital Converter]
        DAC[Digital to Analog Converter]
    end

    %% FPGA Internal Logic
    subgraph Cyclone V FPGA Fabric
        I2S_RX[I2S Receiver Module]
        I2S_TX[I2S Transmitter Module]
        
        %% The DSP Core
        subgraph audio_processor_top.sv
            E0[000: Noise Gate]
            E1[001: High Pitch]
            E2[010: Low Pitch]
            E3[011: Reverb]
            E4[100: Muffled]
            MUX{Output Multiplexer}
        end
        
        VU[VU Meter UI Module]
    end

    %% Routing the signals
    MIC --> ADC
    ADC -- Serial I2S --> I2S_RX
    
    %% Parallel Hardware Execution!
    I2S_RX -- 16-bit audio_in --> E0 & E1 & E2 & E3 & E4
    
    E0 & E1 & E2 & E3 & E4 --> MUX
    SW -- Selects Route --> MUX
    
    MUX -- 16-bit Processed Audio --> I2S_TX
    MUX -- 16-bit Processed Audio --> VU
    
    I2S_TX -- Serial I2S --> DAC
    DAC --> SPK
    VU --> LED

    %% Styling
    style MUX fill:#f96,stroke:#333,stroke-width:2px
    style I2S_RX fill:#bbf,stroke:#333
    style I2S_TX fill:#bbf,stroke:#333
```
