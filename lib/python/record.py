import subprocess
import tempfile
import whisper

model = None

def record_audio_as_text():
    global model
    temp_audio_file = tempfile.mkstemp(suffix=".wav")[1]
    if model == None:
        model = whisper.load_model("small.en")
    rec_process = subprocess.Popen(['rec', '-r', '48000', '-c', '1', '-b', '16', temp_audio_file], stderr=subprocess.DEVNULL)
    print("Recording audio. Press Enter to stop.")
    input()
    rec_process.terminate()
    print(f"Recording stopped. Saved as {temp_audio_file}.")
    result = model.transcribe(temp_audio_file)
    print('[User]:', result["text"])
    # TODO we may want it to repeat it back if we dont want to or cant show the text
    #subprocess.Popen(['say', '--rate', '200', txt_content], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    user_input = input("(Y/n)?")
    if user_input == 'n':
        return record_audio_as_text()
    else:
        return result['text']
