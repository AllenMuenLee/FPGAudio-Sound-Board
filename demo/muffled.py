import numpy as np
from scipy.io import wavfile

def apply_double_muffled(input_file, output_file):
    fs, data = wavfile.read(input_file)

    # Ensure mono
    if len(data.shape) > 1:
        data = data[:, 0]

    audio_in = data.astype(np.float32)
    processed_audio = np.zeros_like(audio_in)

    alpha = 0.01   # smaller = more muffled

    # Filter states
    y1 = 0.0
    y2 = 0.0

    for i in range(len(audio_in)):
        x = audio_in[i]

        # First low-pass
        y1 = y1 + alpha * (x - y1)

        # Second low-pass
        y2 = y2 + alpha * (y1 - y2)

        processed_audio[i] = y2

    # Optional gain compensation (helps restore volume)
    processed_audio *= 1.5

    # Clip back to int16 range
    final_audio = np.clip(processed_audio, -32768, 32767).astype(np.int16)

    wavfile.write(output_file, fs, final_audio)
    print("Muffled effect applied")
