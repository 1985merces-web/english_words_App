import csv
import io
import os
import time
from typing import List, Optional, Tuple
from openai import OpenAI
import concurrent.futures
import threading

# --- CONFIGURATION ---
INPUT_FILE = r'C:\Users\Alex\english_words_app\assets\sets\combined_words.csv'
OUTPUT_FILE = r'C:\Users\Alex\english_words_app\assets\sets\combined_words_ukr.csv'
API_KEY = os.environ.get("OPENAI_API_KEY")
BATCH_SIZE = 10
MAX_WORKERS = 6

client = OpenAI(api_key=API_KEY)

SYSTEM_PROMPT = """
You are a master linguist specializing in English and Ukrainian.
Your task is to transform a CSV of English words into a high-quality Ukrainian flashcard dataset.

MANDATORY RULES FOR EVERY ROW:
1. Column 'Ukr' -> UKRAINIAN TRANSLATION
   - Replace the value with a single, accurate Ukrainian translation.
   - Match the dictionary meaning of the English word.
   - NO explanations, NO alternatives.

2. Columns 'Example1' & 'Example2' -> ENGLISH PHRASES (3-4 words)
3. Columns 'Example3' & 'Example4' -> UKRAINIAN TRANSLATIONS

STRUCTURAL INTEGRITY:
- Output ONLY the CSV rows (8 columns).
- Header: Level,List,Eng,Ukr,Example1,Example2,Example3,Example4
"""

def validate_csv_content(content: str, expected_count: int) -> Optional[str]:
    f = io.StringIO(content.strip())
    reader = csv.reader(f)
    try:
        rows = list(reader)
    except: return None
    if rows and "Level" in rows[0][0]: rows = rows[1:]
    if len(rows) != expected_count: return None
    for row in rows:
        if len(row) < 8 or not all(field.strip() for field in row[3:8]): return None
    output = io.StringIO()
    writer = csv.writer(output, quoting=csv.QUOTE_MINIMAL)
    writer.writerows(rows)
    return output.getvalue()

def process_batch(batch: List[List[str]], batch_idx: int) -> Tuple[int, str]:
    input_str = io.StringIO()
    writer = csv.writer(input_str)
    writer.writerow(["Level", "List", "Eng", "Ukr", "Example1", "Example2"])
    writer.writerows(batch)
    
    for attempt in range(3):
        try:
            response = client.chat.completions.create(
                model="gpt-4o",
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": f"Transform:\n{input_str.getvalue()}"}
                ],
                temperature=0.3
            )
            content = response.choices[0].message.content
            validated = validate_csv_content(content, len(batch))
            if validated: return batch_idx, validated
        except: pass
        time.sleep(2)
    return batch_idx, ""

def main():
    with open(INPUT_FILE, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader)
        all_rows = list(reader)

    LIMIT_GOOD_ROWS = 1002
    print(f"Resuming from line {LIMIT_GOOD_ROWS}...")
    
    with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
        good_lines = f.readlines()[:LIMIT_GOOD_ROWS]
    
    with open(OUTPUT_FILE, 'w', encoding='utf-8', newline='') as f:
        f.writelines(good_lines)

    remaining_rows = all_rows[LIMIT_GOOD_ROWS-1:]
    batches = [remaining_rows[i:i+BATCH_SIZE] for i in range(0, len(remaining_rows), BATCH_SIZE)]
    
    results = {}
    next_to_write = 0
    total = len(batches)
    
    write_lock = threading.Lock()

    print(f"Processing {len(remaining_rows)} rows ({total} batches)...")

    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        future_to_idx = {executor.submit(process_batch, b, i): i for i, b in enumerate(batches)}
        
        for future in concurrent.futures.as_completed(future_to_idx):
            idx, res = future.result()
            with write_lock:
                results[idx] = res
                while next_to_write in results:
                    batch_res = results[next_to_write]
                    if batch_res:
                        with open(OUTPUT_FILE, 'a', encoding='utf-8', newline='') as f:
                            f.write(batch_res)
                            if not batch_res.endswith('\n'): f.write('\n')
                    else:
                        print(f"Warning: Batch {next_to_write+1} failed.")
                    
                    del results[next_to_write]
                    next_to_write += 1
                    print(f"Progress: {next_to_write}/{total} batches written.")

    print("Done!")

if __name__ == "__main__":
    main()
