import csv
import json
import os
import random
import time
from dataclasses import dataclass
from typing import Dict, List, Any, Tuple

from dotenv import load_dotenv
from tqdm import tqdm
from openai import OpenAI

load_dotenv()

INPUT_PATH = os.getenv("INPUT_CSV", "assets/sets/combined_words.csv")
OUTPUT_PATH = os.getenv("OUTPUT_CSV", "assets/sets/new_combined_words.csv")
CHECKPOINT_PATH = os.getenv("CHECKPOINT_JSON", "assets/sets/new_combined_words.checkpoint.json")

MODEL = os.getenv("OPENAI_MODEL", "gpt-5")  # можна змінити, напр. gpt-4o-mini
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "40"))  # 25–60 зазвичай ок
MAX_RETRIES = int(os.getenv("MAX_RETRIES", "6"))

client = OpenAI()

SYSTEM_INSTRUCTIONS = """You are a senior professional linguist, lexicographer, and data editor
specializing in English–Ukrainian vocabulary for language-learning products.

You will receive CSV rows with columns:
Level,List,Eng,Ukr,Example1,Example2

For EACH row:
1) Correct Ukr (professional Ukrainian, natural, no russisms/calques, preserve POS & meaning).
2) Create Example1: 3–4 word English phrase including Eng, no ending punctuation, not a full sentence.
3) Create Example2: 3–4 word Ukrainian phrase including corrected Ukr, no ending punctuation, not a full sentence.
Keep CEFR alignment according to Level (A1..C2): use appropriate complexity.

Return ONLY valid JSON, no markdown, no extra text.
"""

def backoff_sleep(attempt: int) -> None:
    # random exponential backoff (recommended for rate limits)
    # https://platform.openai.com/docs/guides/rate-limits
    base = min(2 ** attempt, 60)
    jitter = random.uniform(0, 1.0)
    time.sleep(base + jitter)

def load_checkpoint() -> Dict[str, Any]:
    if os.path.exists(CHECKPOINT_PATH):
        with open(CHECKPOINT_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    return {"done_indices": []}

def save_checkpoint(done_indices: List[int]) -> None:
    tmp = {"done_indices": sorted(done_indices)}
    os.makedirs(os.path.dirname(CHECKPOINT_PATH), exist_ok=True)
    with open(CHECKPOINT_PATH, "w", encoding="utf-8") as f:
        json.dump(tmp, f, ensure_ascii=False, indent=2)

def normalize_ua(text: str) -> str:
    return " ".join(text.strip().split())

def validate_phrase(phrase: str) -> str:
    phrase = " ".join(phrase.strip().split())
    # Забираємо крапки/знаки в кінці
    while phrase and phrase[-1] in ".!?;:":
        phrase = phrase[:-1].rstrip()
    return phrase

def rows_to_payload(rows: List[Dict[str, str]]) -> str:
    # відправляємо компактним JSON для надійного парсингу
    return json.dumps(rows, ensure_ascii=False)

def call_model(rows: List[Dict[str, str]]) -> List[Dict[str, Any]]:
    """
    Returns list of objects:
    { "index": <int>, "Ukr": "...", "Example1": "...", "Example2": "..." }
    """
    user_prompt = f"""Process these rows. Return JSON array with the same length and order.
Each output object must include:
- index (int) — original row index
- Ukr (string) — corrected Ukrainian translation
- Example1 (string) — 3–4 word English phrase containing Eng
- Example2 (string) — 3–4 word Ukrainian phrase containing Ukr

Input rows (JSON):
{rows_to_payload(rows)}
"""

    for attempt in range(MAX_RETRIES):
        try:
            resp = client.responses.create(
                model=MODEL,
                instructions=SYSTEM_INSTRUCTIONS,
                input=user_prompt,
                # "store" можна лишити false; якщо хочеш логувати в акаунті — true
            )
            text = resp.output_text.strip()
            data = json.loads(text)
            if not isinstance(data, list) or len(data) != len(rows):
                raise ValueError("Model output JSON length mismatch.")
            return data
        except Exception as e:
            # rate limit / transient / parsing errors
            if attempt == MAX_RETRIES - 1:
                raise
            backoff_sleep(attempt)

def read_all_rows() -> Tuple[List[str], List[Dict[str, str]]]:
    with open(INPUT_PATH, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames or []
        rows = []
        for r in reader:
            rows.append(r)
    return fieldnames, rows

def write_header_if_needed(fieldnames: List[str]) -> None:
    if os.path.exists(OUTPUT_PATH):
        return
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    with open(OUTPUT_PATH, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()

def append_rows(fieldnames: List[str], rows: List[Dict[str, str]]) -> None:
    with open(OUTPUT_PATH, "a", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        for r in rows:
            writer.writerow(r)

def main():
    fieldnames, all_rows = read_all_rows()
    if fieldnames != ["Level", "List", "Eng", "Ukr", "Example1", "Example2"]:
        print("WARNING: Unexpected headers:", fieldnames)

    checkpoint = load_checkpoint()
    done = set(checkpoint.get("done_indices", []))

    write_header_if_needed(fieldnames)

    total = len(all_rows)
    pbar = tqdm(total=total, desc="Processing rows", unit="row")

    # якщо вже щось зроблено — прокрутимо прогресбар
    for i in range(total):
        if i in done:
            pbar.update(1)

    # обробка чанками
    i = 0
    while i < total:
        # знайдемо наступний неготовий індекс
        while i < total and i in done:
            i += 1
        if i >= total:
            break

        chunk_indices = []
        chunk = []
        j = i
        while j < total and len(chunk) < CHUNK_SIZE:
            if j not in done:
                r = dict(all_rows[j])
                r["index"] = j  # додаємо індекс для моделі
                chunk.append(r)
                chunk_indices.append(j)
            j += 1

        # виклик моделі
        out = call_model(chunk)

        # застосувати правки й записати
        updated_rows = []
        for in_row, out_row in zip(chunk, out):
            idx = int(out_row.get("index"))
            base = dict(all_rows[idx])

            ukr = normalize_ua(str(out_row.get("Ukr", base.get("Ukr", ""))))
            ex1 = validate_phrase(str(out_row.get("Example1", base.get("Example1", ""))))
            ex2 = validate_phrase(str(out_row.get("Example2", base.get("Example2", ""))))

            base["Ukr"] = ukr
            base["Example1"] = ex1
            base["Example2"] = ex2

            updated_rows.append(base)

        append_rows(fieldnames, updated_rows)

        for idx in chunk_indices:
            done.add(idx)
            pbar.update(1)

        save_checkpoint(list(done))
        i = j

    pbar.close()
    print(f"Done. Output: {OUTPUT_PATH}")
    print(f"Checkpoint: {CHECKPOINT_PATH}")

if __name__ == "__main__":
    main()
