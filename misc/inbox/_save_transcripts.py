from bs4 import BeautifulSoup
from datetime import datetime
from newspaper import Article
from urllib.parse import urlparse, parse_qs
from urllib.request import urlopen, Request
from youtube_transcript_api import YouTubeTranscriptApi
import json
import textwrap
import os
import re
import requests
import sys

def _get_article_text(url):
    print(url)
    req = Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    html = urlopen(req).read()
    soup = BeautifulSoup(html, features="html.parser")
    # may need more https://matix.io/extract-text-from-webpage-using-beautifulsoup-and-python/
    for script in soup(["script", "style"]):
        script.extract()
    text = soup.get_text()
    # break into lines and remove leading and trailing space on each
    lines = (line.strip() for line in text.splitlines())
    # break multi-headlines into a line each
    chunks = (phrase.strip() for line in lines for phrase in line.split("  "))
    # drop blank lines
    text = '\n'.join(chunk for chunk in chunks if chunk)
    return text

import codecs

def print_yt_channel_name(url):
    if "youtube.com" in url:
        req = Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        html = urlopen(req).read().decode('utf-8')
        print(re.findall(r'"channelName":"[^,]*",', html))

def get_newspaper_text(url):
    a = Article(url)
    a.download()
    a.parse()
    return a.text

def youtube_transcript(video_id):
    return " ".join(map(lambda x: x['text'], YouTubeTranscriptApi.get_transcript(video_id)))

def get_transcript_for(url):
    host = re.sub(r'^www\.', '', urlparse(url).hostname)
    if host == "youtube.com":
        video_id = parse_qs(urlparse(url).query)['v'][0]
        tx = youtube_transcript(video_id)
    else:
        tx = get_newspaper_text(url)
    return tx

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

def get_title_of(url):
    response = requests.get(url, headers={'User-Agent': 'Mozilla/5.0'})
    if response.status_code != 200:
        print(response)
        raise Exception("failed to get url "+ url)
    soup = BeautifulSoup(response.content, "html.parser")
    title = soup.title.string
    return title

def main():
    output_path = sys.argv[2]
    with open(sys.argv[1], 'r') as file:
        for line in file:
            url = line.strip()
            title = get_title_of(url)
            transcript_filename = "{output_path}/transcript%2F{title}.txt".format(title=re.sub(r'[^a-zA-Z0-9]', '_', title), output_path=output_path)
            if os.path.exists(transcript_filename):
                continue
            transcript = format_text(get_transcript_for(url))
            print(transcript_filename)
            with open(transcript_filename, 'w') as file:
                file.write(transcript)

if __name__ == '__main__':
    main()
