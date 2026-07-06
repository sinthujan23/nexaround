import json

path = r'C:\Users\User\.gemini\antigravity-ide\brain\bab87e70-3902-4533-b11c-bc2213891254\.system_generated\logs\transcript.jsonl'

with open(path, 'r', encoding='utf-8') as f:
    for line in f:
        if 'Failed host' in line or 'Gemini Proxy' in line:
            # Parse json to print content nicely
            data = json.loads(line)
            print(f"--- TYPE: {data.get('type')} ---")
            content = data.get('content', '')
            # search for the error snippet
            lines = content.split('\n')
            for l in lines:
                if 'Failed host' in l or 'Gemini Proxy' in l or 'Exception' in l or 'error' in l.lower():
                    # print safely without throwing CP1252 encoding errors
                    clean_line = l.encode('ascii', errors='ignore').decode('ascii')
                    print(clean_line)
