#!/usr/bin/env python
from pathlib import Path
import json
import os
import sys

def process_json_to_markdown(json_file_path):
    # Load the JSON data
    try:
        with open(json_file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"Error: File '{json_file_path}' not found.")
        return
    except json.JSONDecodeError:
        print(f"Error: File '{json_file_path}' is not valid JSON.")
        return

    # Create directory based on the JSON filename (without extension)
    dir_name = os.path.splitext(os.path.basename(json_file_path))[0]
    if not os.path.exists(dir_name):
        os.makedirs(dir_name)
        print(f"Created directory: {dir_name}")

    # Process each top-level item
    for item in data:
        item_name = item['name']
        if item_name == '':
            item_name = item["created_at"]

        # Get the name for the markdown file
        if 'name' not in item:
            print(f"Warning: Skipping item without 'name' field")
            continue

        if os.path.exists(os.path.join(dir_name, f"{item_name}.md")):
            #print(f"markdown file {item_name}.md already exists")
            continue

        # Check if chat_messages exists
        if 'chat_messages' not in item:
            print(f"Warning: No chat_messages found for '{item_name}'")
            continue

        # Get created_at date for the file name prefix
        if 'created_at' in item and item['created_at']:
            try:
                # Extract just the date part (before the "T")
                date_prefix = item['created_at'].split('T')[0]
            except (IndexError, AttributeError):
                date_prefix = "unknown-date"
        else:
            date_prefix = "unknown-date"

        # Create markdown content
        markdown_content = f"# {item_name}\n\n"

        sorted_messages = sorted(
            item['chat_messages'],
            key=lambda msg: msg.get('created_at', '0000-00-00T00:00:00Z')
        )

        # Process each chat message
        for message in sorted_messages:
            if 'sender' in message and 'text' in message:
                sender = message['sender']
                text = message['text']

                markdown_content += f"## {sender.capitalize()}\n\n{text}\n\n"
            else:
                print(f"Warning: Skipping message without sender or text in '{item_name}'")

        # Write to markdown file with date prefix
        safe_name = Path(item_name).stem
        file_path = os.path.join(dir_name, f"{date_prefix}_{safe_name}.md")

        # Ask for user confirmation
        #print(markdown_content)
        #print(file_path)
        #user_input = input(f"Process item '{item_name}'? (y/n): ")
        #if user_input.lower() != 'y':
        #    print(f"Skipping {item_name}")
        #    continue

        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(markdown_content)

        print(f"Created markdown file: {file_path}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python script.py <json_file_path>")
    else:
        json_file_path = sys.argv[1]
        process_json_to_markdown(json_file_path)
