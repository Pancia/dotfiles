#!/usr/bin/env python3

from datetime import datetime
from pathlib import Path
from prompt_toolkit import prompt
from prompt_toolkit.completion import FuzzyWordCompleter
import importlib
import json
import openai
import os
import readline
import shutil
import subprocess
import sys
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

openai.api_key = os.environ['OPENAI_API_KEY']

def import_module(name):
    path = os.path.expanduser(f"~/dotfiles/ai/workflows/{name}/main.py")
    spec = importlib.util.spec_from_file_location('module', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.__dict__

def module_execute(module, fun, *args):
    if fun in module:
        return module[fun](*args)

def validate_module(module):
    api = ['init', 'system_prompt', 'response', 'state', 'functions', 'function_call', 'user_command', 'log']
    for fun in api:
        if fun not in module:
            raise NotImplementedError(f"Module <{module['__file__']}> must implement <{fun}>")

def raw_send_chatbot(messages, functions=None):
    kwargs = {'model': "gpt-3.5-turbo-16k",
              'messages': messages}
    if functions: kwargs['functions'] = functions
    return openai.ChatCompletion.create(**kwargs)

def send_message_to_chatbot(state, module, context, message):
    state["history"].append({"role": "user", "content": message})
    log_history(state, module, context)
    module_functions = module_execute(module, 'functions')
    response = raw_send_chatbot(state["history"], functions = module_functions)
    # TODO print tokens used, maybe if we're near the limit?
    print('[tokens used]:', response['usage']['total_tokens'])
    response_message = response["choices"][0]["message"]
    if response_message.get("function_call"):
        function_name = response_message["function_call"]["name"]
        function_args = json.loads(response_message["function_call"]["arguments"])
        function_call_result = module_execute(module, 'function_call', function_name, function_args)
        state['history'].append({"role": "function",
                                 "name": function_name,
                                 "content": function_call_result})
        log_history(state, module, context)
        function_response = raw_send_chatbot(state['history'])
        content = function_response["choices"][0]["message"]["content"]
        state["history"].append({"role": "assistant", "content": content})
        log_history(state, module, context)
        module_execute(module, 'response', 'function_call', content)
    if response_message.get('content'):
        content = response_message['content']
        state["history"].append({"role": "assistant", "content": content})
        log_history(state, module, context)
        module_execute(module, 'response', context, content)
        return content

def dir_glob(directory):
    file_list = []
    for entry in os.listdir(os.path.expanduser(directory)):
        file_list.append(os.path.join(directory, entry))
    return file_list

def input_autocomplete(valid_entries):
    completer = FuzzyWordCompleter(valid_entries)
    while True:
        print(f"[Options]: {', '.join(valid_entries)}")
        print(f"Press <CTRL-D> with no text to cancel.")
        try:
            user_input = prompt("Pick an option: ", completer=completer)
        except EOFError:
            return None
        if user_input in valid_entries:
            return user_input
        else:
            print("Invalid input, please try again.")

def input_commands(global_commands, module_commands):
    valid_entries_dict = {}
    valid_entries_dict |= global_commands
    valid_entries_dict |= module_commands
    valid_entries = valid_entries_dict.keys()
    completer = FuzzyWordCompleter(valid_entries)
    while True:
        print()
        print("[Available Commands]:")
        print('[Global]:', ', '.join(global_commands.keys()))
        print('[Module]:', ', '.join(module_commands.keys()))
        user_input = prompt("Select a command: ", completer=completer)
        if user_input in valid_entries:
            return valid_entries_dict[user_input]
        else:
            print("Invalid input, please try again.")

def log_history(state, module, context=None):
    with open(os.path.join(state["logs_dir"], 'chat_history.json'), "w") as file:
        file.write(json.dumps(state['history'], indent=4))
    module_execute(module, 'log', context, state['history'][-1])

def send_user_message(state, module, context, message):
    return send_message_to_chatbot(state, module, context, message)

def make_logs_dir(state, module):
    logs_dir = os.path.abspath(os.path.join(module['__file__'], os.pardir, "logs", state['timestamp']))
    if not os.path.exists(logs_dir):
        os.makedirs(logs_dir)
    return logs_dir

global_commands = {
        "quit": "quit",
        "change workflow": "workflow",
        "compose message in editor": "editor",
        "record audio": "audio",
        "write message directly": "text",
        }

def init_workflow(state):
    state["history"] = []
    state["timestamp"] = datetime.now().strftime("%Y_%m_%d@%H:%M:%S")
    module = import_module(state["workflow"])
    validate_module(module)
    state["logs_dir"] = make_logs_dir(state, module)
    module_commands = module_execute(module, 'init')
    system_prompt = module_execute(module, 'system_prompt')
    if system_prompt != None:
        state["history"].append({"role": "system", "content": system_prompt})
        log_history(state, module, "system")
    return module, module_commands

def main():
    state = {}
    if len(sys.argv) != 2:
        workflows = [os.path.basename(w) for w in dir_glob("~/dotfiles/ai/workflows/")]
        user_choice = input_autocomplete(workflows)
        if not user_choice:
            print("Workflow required, terminating!")
            sys.exit(1)
        state["workflow"] = user_choice
    else:
        state["workflow"] = sys.argv[1]
    module, module_commands = init_workflow(state)
    try:
        while True:
            print()
            print()
            print("current timestamp:", state["timestamp"])
            print("current workflow:", state["workflow"])
            print("module state:", module_execute(module, 'state'))
            user_input = input_commands(global_commands, module_commands)
            print()
            if user_input == 'quit':
                break
            elif user_input == 'workflow':
                workflows = [os.path.basename(w) for w in dir_glob("~/dotfiles/ai/workflows/")]
                user_choice = input_autocomplete(workflows)
                if not user_choice: continue
                state["workflow"] = user_choice
                init_workflow(state)
            elif user_input == 'editor':
                print("Edit message in editor")
            elif user_input == 'audio':
                user_message = record_audio_as_text()
                context = "audio"
                send_user_message(state, module, context, user_message)
            elif user_input == 'text':
                user_message = input("Press [Enter] to submit.\n")
                context = "text"
                send_user_message(state, module, context, user_message)
            else:
                module_return = module_execute(module, 'user_command', user_input)
                if module_return == None: continue
                context, user_message = module_return
                send_user_message(state, module, context, user_message)
    except (EOFError, KeyboardInterrupt):
        print('\nExiting...')
        sys.exit(0)

if __name__ == "__main__":
   main()
