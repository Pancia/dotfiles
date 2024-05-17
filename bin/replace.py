#!/usr/bin/env python3

import os
import re
import sys

def process_file(file_path, pattern_type, pattern, replacement):
    try:
        with open(file_path, 'r') as file:
            content = file.read()
        if pattern_type == 'literal':
            print(pattern, replacement)
            replacement = replacement.replace('\\n', '\n').replace('\\t', '\t')
            content = content.replace(pattern, replacement)
        elif pattern_type == 'regex':
            content = re.sub(pattern, replacement, content)
        with open(file_path, 'w') as file:
            file.write(content)
        print(f"Processed: {file_path}")
    except Exception as e:
        print(f"Error processing {file_path}: {e}")

def process_folder(folder_path, pattern_type, pattern, replacement):
    try:
        for root, dirs, files in os.walk(folder_path):
            for file_name in files:
                file_path = os.path.join(root, file_name)
                process_file(file_path, pattern_type, pattern, replacement)
    except Exception as e:
        print(f"Error processing folder {folder_path}: {e}")

def main():
    input("PATH PATTERN_TYPE PATTERN REPLACEMENT: did you remember to escape the pattern? (* or <ctrl-c>)")
    path = sys.argv[1]
    # NOTE: escaping the pattern, but not the replacement
    #pattern = r'- \{\{embed \[\[note/context/external/v1\]\]\}\}\n\t- LATER \[\[note/context/internal/v1\]\] #note/context'
    pattern_type = sys.argv[2]
    if pattern_type == "regex":
        pattern = re.compile(sys.argv[3])
    elif pattern_type == "literal":
        pattern = sys.argv[3]
    else:
        print("unrecognized pattern type")
        return 1
    #replacement = r'- {{embed [[note/context/external/v1]]}}\n\t- LATER [[note/context/external/v1]] #note/context'
    replacement = sys.argv[4]
    if os.path.isfile(path):
        process_file(path, pattern_type, pattern, replacement)
    else:
        process_folder(path, pattern_type, pattern, replacement)

if __name__ == '__main__':
    main()
