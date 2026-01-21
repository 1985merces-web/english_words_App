import csv
import io
import os
import time
from typing import List, Optional, Tuple, Dict
from openai import OpenAI
import concurrent.futures
import threading

# --- CONFIGURATION ---
SOURCE_FILE = r'C:\Users\Alex\english_words_app\assets\sets\combined_words.csv'
TARGET_FILE = r'C:\Users\Alex\english_words_app\assets\sets\combined_words_ukr.csv'
FINAL_FILE = r'C:\Users\Alex\english_words_app\assets\sets\combined_words_ukr_fixed.csv'
API_KEY = os.environ.get("OPENAI_API_KEY")
BATCH_SIZE = 10
MAX_WORKERS = 8

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

def validate_csv_content(content: str, expected_count: int) -> Optional[List[List[str]]]:
    f = io.StringIO(content.strip())
    reader = csv.reader(f)
    try:
        rows = list(reader)
    except: return None
    if rows and "Level" in rows[0][0]: rows = rows[1:]
    if len(rows) != expected_count: return None
    for row in rows:
        if len(row) < 8 or not all(field.strip() for field in row[3:8]): return None
    return rows

def process_batch(batch: List[List[str]], batch_idx: int) -> Tuple[int, List[List[str]]]:
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
                    {"role": "user", "content": f"Transform these rows:\n{input_str.getvalue()}"}
                ],
                temperature=0.3
            )
            content = response.choices[0].message.content
            validated_rows = validate_csv_content(content, len(batch))
            if validated_rows:
                return batch_idx, validated_rows
        except: pass
        time.sleep(1)
    return batch_idx, []

def main():
    # 1. Load Source
    print("Loading source data...")
    source_data = []
    with open(SOURCE_FILE, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader)
        for row in reader:
            source_data.append(row)

    # 2. Load existing Ukrainian data
    print("Loading existing Ukrainian data...")
    existing_ukr = {}
    if os.path.exists(TARGET_FILE):
        with open(TARGET_FILE, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            try:
                next(reader) # skip header
                for row in reader:
                    if len(row) >= 8:
                        # Use (Level, List, Eng) as key
                        key = (row[0], row[1], row[2])
                        existing_ukr[key] = row
            except: pass
    
    # 3. Identify missing rows
    missing_batches = []
    current_missing_batch = []
    
    to_be_processed = []
    
    for row in source_data:
        key = (row[0], row[1], row[2])
        if key not in existing_ukr:
            to_be_processed.append(row)
            
    print(f"Total missing rows to process: {len(to_be_processed)}")
    
    if not to_be_processed:
        print("Everything is complete!")
        # Optional: Re-assemble to be sure
    else:
        batches = [to_be_processed[i:i+BATCH_SIZE] for i in range(0, len(to_be_processed), BATCH_SIZE)]
        total = len(batches)
        
        new_results = {}
        
        print(f"Processing {total} batches...")
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            future_to_idx = {executor.submit(process_batch, b, i): i for i, b in enumerate(batches)}
            
            for future in concurrent.futures.as_completed(future_to_idx):
                idx, rows = future.result()
                if rows:
                    for r in rows:
                        new_results[(r[0], r[1], r[2])] = r
                print(f"Progress: {len(new_results)}/{len(to_be_processed)} rows processed.")

        # 4. Merge and Save FINAL_FILE
        print("Assembling final file...")
        with open(FINAL_FILE, 'w', encoding='utf-8', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(["Level", "List", "Eng", "Ukr", "Example1", "Example2", "Example3", "Example4"])
            
            for row in source_data:
                key = (row[0], row[1], row[2])
                if key in existing_ukr:
                    writer.writerow(existing_ukr[key])
                elif key in new_results:
                    writer.writerow(new_results[key])
                else:
                    # Still missing? Write source with empty but it shouldn't happen
                    print(f"Warning: Row {key} still missing!")
                    writer.writerow(row + ["", ""])

    # Swap or just keep FIXED
    print(f"Finished! Result saved to {FINAL_FILE}")

if __name__ == "__main__":
    main()
