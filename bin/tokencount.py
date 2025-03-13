#!/usr/bin/env python3.11

import tiktoken
import sys

def count_tokens(encoding, file_path):
    with open(file_path, 'r', encoding='utf-8') as file:
        text = file.read()
    tokens = encoding.encode(text)
    return len(tokens)

file_path = sys.argv[1]

encoding = tiktoken.get_encoding("cl100k_base")
token_count = count_tokens(encoding, file_path)
print(encoding, token_count)
