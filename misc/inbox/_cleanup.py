from bs4 import BeautifulSoup
import json
import sys

def parse_html_to_json(file_path):
    result = []
    with open(file_path, 'r') as file:
        for line in file:
            soup = BeautifulSoup(line, 'html.parser')
            anchor_tag = soup.find('a')
            if anchor_tag:
                anchor_data = {
                    'url': anchor_tag.get('href', ''),
                    'title': anchor_tag.get_text(strip=True),
                    'date': anchor_tag.get('add_date', '')
                }
                result.append(anchor_data)
    return result

def main():
    file_path = sys.argv[1]
    try:
        json_data = parse_html_to_json(file_path)
        with open(sys.argv[2], 'w') as json_file:
            json.dump(json_data, json_file, indent=4)
        print(f'Conversion successful. Output saved to "{sys.argv[2]}".')
    except Exception as e:
        print(f'An error occurred: {e}')

if __name__ == "__main__":
    main()
