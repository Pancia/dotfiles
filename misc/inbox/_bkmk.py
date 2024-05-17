from bs4 import BeautifulSoup
from datetime import datetime
from urllib.parse import urlparse, parse_qs
from urllib.request import urlopen, Request
import json
import os
import time
import re
import requests
import subprocess
import sys

def escape_title(title):
    return re.sub(r'[^a-zA-Z0-9]', '_', title)

def get_transcript_for(path, title):
    filename = path+"/transcripts/transcript%2F{title}.txt".format(title=escape_title(title))
    with open(filename, 'r') as file:
        return file.read()

def format_transcript(text):
    result = []
    current_group = []
    for string in text.split('\n'):
        if string == '':
            if current_group:
                result.append(current_group)
                current_group = []
        else:
            current_group.append(string)
    if current_group:
        result.append(current_group)
    formatted_result = []
    for group in result:
        if len(group) > 1:
            formatted_result.append(' '*4 + f'- {group[0]}')
            formatted_result.extend([' '*4 + item for item in group[1:]])
        else:
            formatted_result.append(' '*4 + f'- {group[0]}')
    return '\n'.join(formatted_result)

def _ask_user(prompt):
    while True:
        user_input = input(prompt)
        if user_input != '':
            return user_input
        else:
            print("Invalid input, please try again.")

note_template="""
note/source:: [[note/source/{source}]]
note/author:: [[note/author/{author}]]
note/link:: {link}
note/date:: [[{date}]]
note/para:: [[para/{para}]]

- {{{{embed [[note/summary/v1]]}}}}
    - LATER [[note/summary/v1]] #note/summary
- {{{{embed [[note/context/internal/v1]]}}}}
    - LATER [[note/context/internal/v1]] #note/context
- {{{{embed [[note/context/external/v1]]}}}}
    - LATER [[note/context/external/v1]] #note/context
- {{{{embed [[note/context/social/v1]]}}}}
    - LATER [[note/context/social/v1]] #note/context
- {{{{embed [[note/context/current-status/v1]]}}}}
    - LATER [[note/context/current-status/v1]] #note/context
- #note/transcript title: {title}
{transcript}
"""

def print_yt_channel_name(url):
    if "youtube.com" in url:
        req = Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        html = urlopen(req).read().decode('utf-8')
        print([s.replace('"', ' ') for s in re.findall(r'"channelName":"[^,]*",', html)])
        print([s.replace('"', ' ') for s in re.findall(r'"author":"[^,]*",', html)])

def clear_terminal():
    subprocess.run(r"printf '\e]1337;ClearScrollback\a'", shell=True)

def get_title_of(url):
    response = requests.get(url)
    if response.status_code != 200:
        raise Exception("failed to get url "+ url)
    soup = BeautifulSoup(response.content, "html.parser")
    title = soup.title.string
    return title

def main():
    print(sys.argv[1])
    assets_path = sys.argv[2]
    with open(sys.argv[1], 'r') as file:
        for line in file:
            url = line.strip()
            title = get_title_of(url)
            note_filename = "notes/notes%2F{title}.md".format(title=escape_title(title))
            print(note_filename)
            if os.path.exists(note_filename):
                continue
            date = datetime.fromtimestamp(time.time()).strftime("%Y_%m_%d")
            transcript = format_transcript(get_transcript_for(assets_path, title))
            print(transcript)
            print('date:', date)
            print('title:', title)
            print('url:', url)
            print_yt_channel_name(url)
            author = 'inbox/fixme/author' #input('AUTHOR:')
            source = 'inbox/fixme/source' #input('SOURCE:')
            os.system("ag '\[\[para/(.*)\]\]' notes/ -o --no-filename | sort | uniq")
            para = 'inbox/fixme/para' #input('PARA: What Project/Area/Resource?')
            values={
                    'title': title,
                    'link': url,
                    'date': date,
                    'transcript': transcript,
                    'source': source,
                    'author': author,
                    'para': para,
                    }
            note_content = note_template.format(**values)
            with open(note_filename, 'w') as file:
                file.write(note_content)
            #input('continue? [Enter|<C-C>|<C-D>]:')
            clear_terminal()

if __name__ == '__main__':
    main()
