import os
import sys
from bs4 import BeautifulSoup
from datetime import datetime

def extract_date(date_str):
    try:
        date_obj = datetime.strptime(date_str, "%b %d, %Y, %I:%M:%S %p")
        return date_obj.strftime("%Y_%m_%d")
    except ValueError:
        return None

def extract_content(html):
    soup = BeautifulSoup(html, 'html.parser')
    content_div = soup.find('div', class_='content')
    content = content_div.get_text('\n  - ')
    heading_div = soup.find('div', class_='heading')
    heading = heading_div.get_text().strip()
    date = extract_date(heading)
    content = "- #gkeep/imported #journal\n  - " + content
    return [content, date]

if len(sys.argv) < 2:
    print("Please provide a folder path as an argument.")
    sys.exit(1)

folder_path = sys.argv[1]
dest_path = sys.argv[2]

input("Did you export and download the gkeep takeout?")

for filename in os.listdir(folder_path):
    file_path = os.path.join(folder_path, filename)
    if file_path.endswith('.html'):
        try:
            with open(file_path, 'r', encoding='utf-8') as file:
                html_content = file.read()
                [content_text, date] = extract_content(html_content)
                if content_text:
                    print(f"append {filename} to {dest_path}/{date}.md")
                    with open(f"{dest_path}/{date}.md", 'a') as file:
                        file.write("\n"+content_text)
                    print("-" * 30)
        except Exception as e:
            print(f"Error processing {filename}: {e}")
