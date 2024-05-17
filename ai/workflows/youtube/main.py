from urllib.parse import urlparse, parse_qs
from youtube_transcript_api import YouTubeTranscriptApi
import sys
import yt_dlp

VIDEO_ID = None

def _extract_chapters(video_id):
    URL = 'https://www.youtube.com/watch?v='+video_id
    ydl_opts = {'quiet': True}
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(URL, download=False)
        chapters = info["chapters"]
    return chapters

def _raw_transcript(video_id):
    return YouTubeTranscriptApi.get_transcript(video_id)

def _text_transcript(video_id):
    return " ".join(map(lambda x: x['text'], _raw_transcript(video_id)))

def system_prompt(): None

def _ask_user(prompt):
    while True:
        user_input = input(prompt)
        if user_input != '':
            return user_input
        else:
            print("Invalid input, please try again.")

def init():
    global VIDEO_ID
    user_input = _ask_user("Youtube video id:")
    try:
        parsed = urlparse(user_input)
        qp = parse_qs(parsed.query)
        VIDEO_ID = qp['v'][0]
    except:
        VIDEO_ID = user_input
    return {
            "display transcript": "transcript",
            "pretty formatted transcript": "pretty_transcript",
            "summary": "summary",
            "chapter summary": "chapter_summary",
            }

def response(command, text):
    print('[YOUTUBE]:', command, text)

def state():
    global VIDEO_ID
    return {'video_id': VIDEO_ID}

def functions(): return []

def function_call(): pass

def log(*args): pass

def user_command(command):
    global VIDEO_ID
    if command == 'transcript':
        print(_text_transcript(VIDEO_ID))
        # TODO pbcopy it ?
        return
    elif command == 'pretty_transcript':
        return command, "Format the following text without changing any of words, only affect the formatting: \n" + _text_transcript(VIDEO_ID)
    elif command == 'chapter_summary':
        chapters = _extract_chapters(VIDEO_ID)
        if chapters:
            transcript_by_chapters = []
            for chapter in chapters:
                transcript_by_chapters.append(f"[chapter] {chapter['title']}:\n")
            for item in _raw_transcript(VIDEO_ID):
                for i, chapter in enumerate(chapters):
                    if item['start'] >= chapter['start_time'] and item['start'] <= chapter['end_time']:
                        transcript_by_chapters[i] += " " + item['text']
            return command, """
            Summarize each [chapter] in their own section.

            An example summary:
            ```
            chapter 1 [title]:
            the summary of chapter 1 goes here.

            chapter 2 [title]:
            the summary of chapter 2 goes here.
            ```

            [transcript]:
            \n""" + '\n\n'.join(transcript_by_chapters)
    elif command == 'summary':
        return command, """
        Summarize the [transcript] into a single paragraph.
        Then create up to 10 bullet point summaries of key points or important moments, each should start with an appropriate emoji.

        An example summary:
        ```
        The summary of the entire transcript goes here.

        ## bullet points
        - [emoji] first key moment summary here.
        - [emoji] second key moment summary here.
        ```

        Make sure to include both the summary and the emoji bullet points.

        [transcript]:\n
        """ + _text_transcript(VIDEO_ID)
