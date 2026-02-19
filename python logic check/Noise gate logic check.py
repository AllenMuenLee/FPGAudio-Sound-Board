import numpy as np
from scipy.io import wavfile

# 1. Load your audio
fs, data = wavfile.read('input.wav')
# Normalize to 16-bit range (-32768 to 32767)
audio_in = data.astype(np.int16)

# 2. Apply your Verilog logic
threshold = 2048
processed_audio = np.where(np.abs(audio_in) > threshold, audio_in, 0)

# 3. Save to hear the result
wavfile.write('output_filtered.wav', fs, processed_audio.astype(np.int16))
