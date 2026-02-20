import sounddevice as sd
from scipy.io import wavfile
import numpy as np

def apply_noise_gate(input_file, output_file):
    fs, data = wavfile.read(input_file)
    audio_in = data.astype(np.int16)
    processed_audio = np.zeros_like(audio_in)

    open_threshold = 1000
    close_threshold = 500
    
    is_open = False
    
    gain = 0.01
    floor_gain = 0.01
    atk_step, rls_step = 0.01, 0.01

    for i in range(len(audio_in)):
        sample = audio_in[i]
        
        abs_v = abs(sample)
        if abs_v > open_threshold:
            is_open = True
        elif abs_v < close_threshold:
            is_open = False
            
        if is_open:
            gain = min(1.0, gain + atk_step)
        else:
            gain = max(floor_gain, gain - rls_step)

        processed_audio[i] = sample * gain

    final_audio = np.clip(processed_audio, -32768, 32767).astype(np.int16)
    wavfile.write(output_file, fs, final_audio)
    print("Noise gate applied")