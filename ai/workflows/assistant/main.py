import sys
import subprocess

def system_prompt(): None

def functions():
    return [{"name": "start_timer",
             "description": "Starts a timer for a given number of seconds, with an optional reminder text string.",
             "parameters": {
                 "type": "object",
                 "properties": {
                     "time": {
                         "type": "number",
                         "description": "The length of the timer in seconds",
                         },
                     "reminder": {
                         "type": "string",
                         "description": "The text to tell the user when the timer goes off",
                         }
                     },
                 "required": ["time"],
                 },
             }
            ]

def function_call(name, args):
    print(f"CALL {name} {args}")
    return f"timer started! {args}"

def init():
    return 'assistant'

def response(context, text):
    pass
    print(f"[module assistant]: context={context}\n{text}")

def state():
    return {}

def log(*args):
    pass

def ask_user():
    pass
