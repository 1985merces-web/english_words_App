import csv
import os
import time
import concurrent.futures
from typing import List

# Requires: pip install openai
try:
    from openai import OpenAI
except ImportError:
    print("Please install the openai library: pip install openai")
    exit(1)

# --- CONFIGURATION ---
INPUT_FILE = r'C:\Users\Alex\english_words_app\assets\sets\combined_words.csv'
OUTPUT_FILE = r'C:\Users\Alex\english_words_app\assets\sets\combined_words_ukr_gpt4o.csv'
API_KEY = os.environ.get("OPENAI_API_KEY")
BATCH_SIZE = 20  # Number of lines to process in one API call
MAX_WORKERS = 5  # Parallel requests

if not API_KEY:
    print("Error: OPENAI_API_KEY not found. Please set it as an environment variable or edit the script.")
    exit(1)

client = OpenAI(api_key=API_KEY)

SYSTEM_PROMPT = """
You are an autonomous linguistic and data‑processing system.
Input columns: Level, List, Eng, Ukr, Example1, Example2
Output columns: Level, List, Eng, Ukr, Example1, Example2, Example3, Example4

Objectives:
1. Translation correction (column: Ukr):
   - Review every Ukrainian translation.
   - Correct inaccurate, literal, or stylistically poor translations.
   - Ensure all translations are professional, natural, and linguistically correct in UKRAINIAN.
2. Improve English example phrases (columns: Example1, Example2):
   - Generate short natural ENGLISH phrases (3–4 words).
   - MUST be in ENGLISH.
3. Generate Ukrainian example phrases (columns: Example3, Example4):
   - Generate two short UKRAINIAN phrases (3–4 words).
   - MUST be in UKRAINIAN.

CRITICAL RULES TO AVOID BUGS:
- Example1 & Example2 MUST BE ENGLISH ONLY.
- Example3 & Example4 MUST BE UKRAINIAN ONLY.
- Do not mix languages within a column.

Output Format Requirements:
- Return ONLY valid CSV data.
- NO markdown formatting (no ```csv blocks).
- Strictly maintain the column order: Level,List,Eng,Ukr,Example1,Example2,Example3,Example4
- Do not omit any rows.
"""

def process_batch(batch_lines: List[str]) -> str:
    """Sends a batch of CSV lines to the LLM with retry logic."""
    csv_text = "".join(batch_lines)
    max_retries = 5
    base_delay = 2

    for attempt in range(max_retries):
        try:
            response = client.chat.completions.create(
                model="gpt-4o", # User requested gpt-4o for high quality
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": f"Process these lines:\n{csv_text}"}
                ],
                temperature=0.3
            )
            return response.choices[0].message.content
        except Exception as e:
            print(f"Error processing batch (Attempt {attempt+1}/{max_retries}): {e}")
            if attempt < max_retries - 1:
                sleep_time = base_delay * (2 ** attempt) # Exponential backoff
                print(f"Retrying in {sleep_time} seconds...")
                time.sleep(sleep_time)
            else:
                print("Max retries reached. Batch failed.")
                return ""
    return ""

def main():
    if not os.path.exists(INPUT_FILE):
        print(f"Input file not found: {INPUT_FILE}")
        return

    print(f"Preparing to process {INPUT_FILE} for English -> Ukrainian (High Quality)...")
    
    with open(INPUT_FILE, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    header = lines[0]
    data_lines = lines[1:]
    
    # Check if output file exists to RESUME
    start_index = 0
    if os.path.exists(OUTPUT_FILE):
        print(f"Output file found. Checking for resume...")
        with open(OUTPUT_FILE, 'r', encoding='utf-8') as f_out_read:
            existing_lines = f_out_read.readlines()
            # If we have more than just header
            if len(existing_lines) > 1:
                # Calculate how many data lines are already done
                # Subtract 1 for header
                lines_done = len(existing_lines) - 1
                start_index = lines_done
                print(f"Resuming from line {start_index}...")
            else:
                # Just header exists, overwrite or append? Let's just append.
                if len(existing_lines) == 0:
                     with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
                        f.write("Level,List,Eng,Ukr,Example1,Example2,Example3,Example4\n")
    else:
        # Write new Header for Ukr Output (8 Columns)
        new_header = "Level,List,Eng,Ukr,Example1,Example2,Example3,Example4\n"
        with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
            f.write(new_header)
    
    total_lines = len(data_lines)
    
    # Slice the data_lines to skip what is already done
    remaining_lines = data_lines[start_index:]
    
    if not remaining_lines:
        print("All lines appear to be processed!")
        return

    batches = []
    current_batch = []
    
    for line in remaining_lines:
        current_batch.append(line)
        if len(current_batch) >= BATCH_SIZE:
            batches.append(current_batch)
            current_batch = []
    if current_batch:
        batches.append(current_batch)
        
    print(f"Starting processing of {len(remaining_lines)} remaining lines (Total: {total_lines}) to '{OUTPUT_FILE}'...")
    print(f"Model: gpt-4o (High Cost/Quality)")
    
    processed_count = start_index 
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        future_to_batch = {executor.submit(process_batch, batch): batch for batch in batches}
        
        with open(OUTPUT_FILE, 'a', encoding='utf-8', buffering=1) as f_out:
            for future in concurrent.futures.as_completed(future_to_batch):
                result = future.result()
                if result:
                    # Clean the result
                    clean_result = result.replace("```csv", "").replace("```", "").strip()
                    if not clean_result.endswith('\n'):
                        clean_result += '\n'
                    
                    f_out.write(clean_result)
                    
                    processed_count += len(future_to_batch[future])
                    if processed_count % 100 == 0 or processed_count >= total_lines:
                        print(f"Progress: {processed_count}/{total_lines} lines completed.")
                else:
                    print("Batch failed.")

    print(f"Done! Check {OUTPUT_FILE}")

if __name__ == "__main__":
    main()
