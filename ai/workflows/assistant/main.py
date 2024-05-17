import sys
import subprocess

def system_prompt(): None

# TASKs:
# - start a cron job every minute that runs ./timer.py
# - starting a timer will call timer.py
#   - send will create a timer json file in `timers/${trigger_after}.json`
#   - cron.py will look at all timer file name to figure out which to trigger_after
# - ai-chat will need to support starting a workflow with some prefilled system and assistant messages

def functions():
    return [{"name": "start_timer",
             "description": "Starts a timer for a given number of minutes, with an optional reminder text string.",
             "parameters": {
                 "type": "object",
                 "properties": {
                     "time": {
                         "type": "number",
                         "description": "The length of the timer in minutes",
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
    return {}

def response(context, text):
    pass
    print(f"[module assistant]: context={context}\n{text}")

def state():
    return {}

def log(*args):
    pass

def user_command():
    pass
