def apply_muffled(input_file, output_file):
    fs, data = wavfile.read(input_file)
    
    audio_in = data.astype(np.int16)
    processed_audio = np.zeros_like(audio_in, dtype=np.float32)

    alpha = 0.05   # smaller = more muffled

    y_prev = 0.0

    for i in range(len(audio_in)):
        x = float(audio_in[i])
        
        # First-order low-pass filter
        y = y_prev + alpha * (x - y_prev)
        
        processed_audio[i] = y
        y_prev = y

    final_audio = np.clip(processed_audio, -32768, 32767).astype(np.int16)
    wavfile.write(output_file, fs, final_audio)
    print("Muffled effect applied")
