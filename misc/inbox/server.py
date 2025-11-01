from bs4 import BeautifulSoup
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs
from urllib.request import urlopen, Request
from youtube_transcript_api import YouTubeTranscriptApi
import codecs
import json
import os
import re
import subprocess
import sys
import textwrap
import traceback

def escape_title(title):
    return re.sub(r'[^a-zA-Z0-9]', '_', title)

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

def youtube_transcript(video_id):
    return " ".join(map(lambda x: x['text'], YouTubeTranscriptApi.get_transcript(video_id)))

def get_transcript_for(url, pageContent):
    host = re.sub(r'^www\.', '', urlparse(url).hostname)
    if host == "youtube.com":
        video_id = parse_qs(urlparse(url).query)['v'][0]
        yttx = youtube_transcript(video_id)
        tx = format_text(yttx)
    else:
        tx = pageContent
    return format_transcript(tx)

def paragraph(text, n):
    lines = text.split('\n')
    lines_with_empty_strings = [line if (i + 1) % (n+1) != 0 else '' for i, line in enumerate(lines)]
    result_text = '\n'.join(lines_with_empty_strings)
    return result_text

def format_text(text, width=80):
    if len(re.findall('\n', text)) == 0:
        wrapped_text = textwrap.fill(text, width=width)
        formatted_text = paragraph(wrapped_text, 5)
        return formatted_text
    else:
        return text

class MyRequestHandler(BaseHTTPRequestHandler):
    def _send_response(self, status, content_type, content):
        self.send_response(status)
        self.send_header('Content-type', content_type)
        self.end_headers()
        self.wfile.write(content)
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        command = "ag -o --no-filename '\[\[para/([^\]]*)\]\]' notes/ ~/ProtonDrive/Dropbox/wiki/personal/pages/ | sort | uniq"
        result = subprocess.run(command, shell=True, stdout=subprocess.PIPE, text=True)
        response = result.stdout
        self.wfile.write(response.encode('utf-8'))
    def do_POST(self):
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length).decode('utf-8')
            parsed_path = urlparse(self.path)
            path = parsed_path.path
            if path.startswith('/saveNotes'):
                try:
                    json_data = json.loads(body)
                    url = json_data["url"]
                    title = json_data["title"]
                    note = json_data["note"]
                    pageContent = json_data["pageContent"]
                    date = json_data["date"]
                    transcript = get_transcript_for(url, pageContent)
                    note += f"\n- #note/transcript title: {title}\n{transcript}"
                    print(f"final note: {note}")
                    note_filename = f"notes/notes%2F{escape_title(title)}.md"
                    with open(note_filename, 'w') as file:
                        file.write(note)
                    response_content = note.encode('utf-8')
                    status = 200
                except json.JSONDecodeError as e:
                    print(f"Error parsing JSON: {e}")
                    response_content = b''
                    status = 400
            elif path.startswith('/moveNote'):
                json_data = json.loads(body)
                title = json_data['title']
                note_filename = f"notes/notes%2F{escape_title(title)}.md"
                print(f"mv {note_filename} ~/ProtonDrive/Dropbox/wiki/personal/pages/")
                os.system(f"mv {note_filename} ~/ProtonDrive/Dropbox/wiki/personal/pages/")
                response_content = b''
                status = 200
            else:
                print(f"Error: unknown POST path: {path}")
                response_content = b''
                status = 400
            self._send_response(status, 'text/plain', response_content)
        except Exception as e:
            print(f"Unexpected Error: {e}")
            traceback.print_exc()
            self._send_response(500, 'text/plain', b'')

def run_server(port=3579):
    server_address = ('', port)
    httpd = HTTPServer(server_address, MyRequestHandler)
    print(f"Started at: {datetime.now()}")
    print(f"On port: {port}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
        print("Server stopped.")

if __name__ == '__main__':
    run_server()
