import sounddevice as sd
from scipy.io import wavfile
import numpy as np

def record_raw_audio(filename, duration=5, fs=44100):
    print(f"Recording for {duration} seconds")
    
    recording = sd.rec(int(duration * fs), samplerate=fs, channels=1, dtype='int16')
    
    sd.wait()
    print("Recording finished")
    wavfile.write(filename, fs, recording)