import csv
import os
import time
import io
import concurrent.futures
from typing import List, Optional

# Requires: pip install openai
try:
    from openai import OpenAI
except ImportError:
    print("Please install the openai library: pip install openai")
    exit(1)

# --- CONFIGURATION ---
INPUT_FILE = r'C:\Users\Alex\english_words_app\assets\sets\combined_words.csv'
OUTPUT_FILE = r'C:\Users\Alex\english_words_app\new_combined_words.csv'
API_KEY = os.environ.get("OPENAI_API_KEY")
BATCH_SIZE = 10  # Smaller batch for better reliability
MAX_WORKERS = 3  # Lower parallelism to stay within rate limits and ensure ordering if needed

if not API_KEY:
    print("Error: OpenAI API key not found.")
    exit(1)

client = OpenAI(api_key=API_KEY)

SYSTEM_PROMPT = """
You are a master linguist specializing in English and International Portuguese.
Your task is to transform a CSV of English words into a high-quality Portuguese flashcard dataset.

MANDATORY RULES FOR EVERY ROW:
1. Column 'Ukr' -> PORTUGUESE TRANSLATION
   - Replace the value with a single, neutral, accurate Portuguese translation.
   - Match the dictionary meaning of the English word.
   - NO explanations, NO parentheses, NO alternatives.

2. Columns 'Example1' & 'Example2' -> PORTUGUESE PHRASES
   - For each row, think of two natural, common ENGLISH phrases (3-4 words each).
   - Translate these phrases into PORTUGUESE (3-4 words each).
   - The Portuguese phrases must be natural usage, NOT literal translations, and NOT generic patterns.
   - AVOID patterns like "tipo de...", "um exemplo...", "frase com...". Use real-world usage.
   - NO punctuation at the end.
   - Example 1: If word is 'table', Example 1 could be 'em cima da mesa' (on the table).
   - Example 2: 'uma mesa redonda' (a round table).

STRUCTURAL INTEGRITY:
- Output ONLY the CSV rows.
- Header must be: Level,List,Eng,Ukr,Example1,Example2
- Maintain EXACT order: Level,List,Eng,Ukr,Example1,Example2
- DO NOT change Level or List columns.
- One row in, one row out. Do not merge or skip rows.
- Use commas as separators. If a field contains a comma, wrap the field in double quotes.

Your response must start immediately with the CSV data.
"""

def validate_csv_content(content: str, expected_count: int) -> Optional[str]:
    """Validates that the returned content has the expected number of rows and is valid CSV."""
    f = io.StringIO(content.strip())
    reader = csv.reader(f)
    rows = list(reader)
    
    # Check if header is included and strip it
    if rows and "Level" in rows[0][0]:
        rows = rows[1:]
        
    if len(rows) != expected_count:
        print(f"Validation failed: Expected {expected_count} rows, got {len(rows)}")
        return None
    
    # Check for empty columns in required fields
    for row in rows:
        if len(row) < 6:
            print(f"Validation failed: Incomplete row {row}")
            return None
        if not row[3] or not row[4] or not row[5]:
            print(f"Validation failed: Empty fields in row {row}")
            return None

    # Re-encode as CSV string
    output = io.StringIO()
    writer = csv.writer(output, quoting=csv.QUOTE_MINIMAL)
    writer.writerows(rows)
    return output.getvalue()

def process_batch(batch_lines: List[str]) -> str:
    """Sends a batch of CSV lines to the LLM with retry logic."""
    header = "Level,List,Eng,Ukr,Example1,Example2\n"
    csv_text = header + "".join(batch_lines)
    expected_count = len(batch_lines)
    
    for attempt in range(4):
        try:
            response = client.chat.completions.create(
                model="gpt-4o",
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": f"Process these {expected_count} rows:\n{csv_text}"}
                ],
                temperature=0.2
            )
            content = response.choices[0].message.content.strip()
            # Remove markdown blocks
            if "```" in content:
                content = content.split("```")[1]
                if content.startswith("csv"):
                    content = content[3:]
            
            validated_csv = validate_csv_content(content, expected_count)
            if validated_csv:
                return validated_csv
            else:
                print(f"Retry {attempt+1}: Invalid row count or content.")
                time.sleep(2)
        except Exception as e:
            print(f"Error processing batch: {e}")
            time.sleep(5)
            
    return ""

def main():
    if not os.path.exists(INPUT_FILE):
        print(f"Input file not found: {INPUT_FILE}")
        return

    with open(INPUT_FILE, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    header = lines[0]
    data_lines = lines[1:]
    
    # Resume logic
    start_index = 0
    if os.path.exists(OUTPUT_FILE):
        with open(OUTPUT_FILE, 'r', encoding='utf-8') as f_out_read:
            existing_lines = f_out_read.readlines()
            if len(existing_lines) > 1:
                # Count only lines that look like valid data or have content
                # To be extra safe about partial lines or empty lines at the end:
                clean_lines = [l for l in existing_lines if l.strip()]
                start_index = len(clean_lines) - 1
                print(f"Resuming from row {start_index}...")

    if start_index == 0:
        with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
            f.write("Level,List,Eng,Ukr,Example1,Example2\n")

    remaining_data = data_lines[start_index:]
    if not remaining_data:
        print("All rows already processed.")
        return

    batches = []
    for i in range(0, len(remaining_data), BATCH_SIZE):
        batches.append(remaining_data[i:i+BATCH_SIZE])

    print(f"Processing {len(remaining_data)} remaining lines in {len(batches)} batches...")

    # For safety and to maintain order without complex logic, we'll process sequentially
    # given the scale (10k rows) and the need for high quality.
    for i, batch in enumerate(batches):
        print(f"Batch {i+1}/{len(batches)} (Rows {i*BATCH_SIZE} to {min((i+1)*BATCH_SIZE, len(data_lines))})...")
        result = process_batch(batch)
        if result:
            with open(OUTPUT_FILE, 'a', encoding='utf-8', newline='') as f_out:
                f_out.write(result.strip() + "\n")
        else:
            print(f"CRITICAL FAILURE: Failed to process batch {i+1}. Stopping to avoid further corruption.")
            break

    print("Processing complete. Verification required.")

if __name__ == "__main__":
    main()
