from youtube_transcript_api import YouTubeTranscriptApi
import sys
import yt_dlp

VIDEO_ID = None

def extract_chapters(video_id):
    URL = 'https://www.youtube.com/watch?v='+video_id
    ydl_opts = {'quiet': True}
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(URL, download=False)
        chapters = info["chapters"]
    return chapters

def raw_transcript(video_id):
    return YouTubeTranscriptApi.get_transcript(video_id)

def text_transcript(video_id):
    return " ".join(map(lambda x: x['text'], raw_transcript(video_id)))

def system_prompt(): None

def init(): # EXPORT
    global VIDEO_ID
    print("[YOUTUBE] INIT!", sys.argv)
    VIDEO_ID = input("Youtube video id:")
    return 'youtube'

def response(command, text): # EXPORT
    print('[chatgpt]:', command, text)

def state(): # EXPORT
    global VIDEO_ID
    return {'video_id': VIDEO_ID}

def log(*args): None

def ask_user(): # EXPORT
    global VIDEO_ID
    print("[YOUTUBE] SELECT COMMAND:")
    cmd = input("[t] transcript, [s] summary, [c] chapter summary, [p] pretty transcript:")
    if cmd == 't':
        print(text_transcript(VIDEO_ID))
        # TODO pbcopy it ?
        return
    elif cmd == 'p':
        return cmd, "Format the following text without changing any of words, only affect the formatting: \n" + text_transcript(VIDEO_ID)
    elif cmd == 'c':
        chapters = extract_chapters(VIDEO_ID)
        if chapters:
            transcript_by_chapters = []
            for chapter in chapters:
                transcript_by_chapters.append(f"[chapter] {chapter['title']}:\n")
            for item in raw_transcript(VIDEO_ID):
                for i, chapter in enumerate(chapters):
                    if item['start'] >= chapter['start_time'] and item['start'] <= chapter['end_time']:
                        transcript_by_chapters[i] += " " + item['text']
            return cmd, """
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
    elif cmd == 's':
        return cmd, """
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
        """ + text_transcript(VIDEO_ID)
