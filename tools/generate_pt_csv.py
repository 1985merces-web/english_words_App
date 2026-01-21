import csv
import json
import os
import random
import time
from typing import Dict, List, Tuple
from urllib import request, error


INPUT_CSV = os.getenv("INPUT_CSV", "assets/data/sets/en.csv")
OUTPUT_CSV = os.getenv("OUTPUT_CSV", "assets/data/sets/pt.csv")
MODEL = os.getenv("OPENAI_MODEL", "gpt-4o")
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "40"))
MAX_RETRIES = int(os.getenv("MAX_RETRIES", "6"))


def load_dotenv_if_needed(path: str = ".env") -> None:
    if os.getenv("OPENAI_API_KEY"):
        return
    if not os.path.exists(path):
        return
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            key = key.strip()
            val = val.strip().strip('"').strip("'")
            if key and val and not os.getenv(key):
                os.environ[key] = val


def read_rows() -> List[Dict[str, str]]:
    with open(INPUT_CSV, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        rows = []
        for r in reader:
            rows.append(r)
    return rows


def get_resume_index() -> int:
    if not os.path.exists(OUTPUT_CSV):
        return 0
    with open(OUTPUT_CSV, "r", encoding="utf-8", newline="") as f:
        lines = [l for l in f.read().splitlines() if l.strip()]
    # subtract header if present
    if lines and lines[0].startswith("Level,"):
        return max(0, len(lines) - 1)
    return len(lines)


def write_header_if_needed() -> None:
    if os.path.exists(OUTPUT_CSV):
        return
    os.makedirs(os.path.dirname(OUTPUT_CSV), exist_ok=True)
    with open(OUTPUT_CSV, "w", encoding="utf-8", newline="") as f:
        f.write("Level,List,Word1,Word2\n")


def call_openai(batch: List[Dict[str, str]]) -> List[Dict[str, str]]:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is not set.")

    system_prompt = (
        "You are a professional bilingual lexicographer. "
        "Translate English words into Brazilian Portuguese (pt-BR). "
        "Return only JSON."
    )
    user_prompt = (
        "Translate each item. Requirements:\n"
        "- word1: translation of 'word'\n"
        "- word2: translation of 'synonym' (empty string if synonym is empty)\n"
        "- Use neutral dictionary forms, no punctuation at the end.\n"
        "- Return a JSON array of objects with keys: index, word1, word2\n"
        "- Keep the same order and length.\n\n"
        f"Input JSON:\n{json.dumps(batch, ensure_ascii=False)}"
    )

    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        "temperature": 0.2,
    }

    data = json.dumps(payload).encode("utf-8")
    req = request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=data,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )

    with request.urlopen(req, timeout=120) as resp:
        raw = resp.read().decode("utf-8")
    obj = json.loads(raw)
    content = obj["choices"][0]["message"]["content"].strip()

    # Defensive parsing in case of stray text
    start = content.find("[")
    end = content.rfind("]")
    if start == -1 or end == -1:
        raise ValueError("Model response is not JSON array.")
    return json.loads(content[start : end + 1])


def translate_batch(batch_rows: List[Tuple[int, Dict[str, str]]]) -> List[Dict[str, str]]:
    payload = []
    for idx, row in batch_rows:
        payload.append(
            {
                "index": idx,
                "word": row.get("Word", "").strip(),
                "synonym": row.get("Synonym", "").strip(),
            }
        )

    for attempt in range(MAX_RETRIES):
        try:
            result = call_openai(payload)
            if not isinstance(result, list) or len(result) != len(payload):
                raise ValueError("JSON length mismatch.")
            # Validate indices and fields
            for item in result:
                if "index" not in item or "word1" not in item or "word2" not in item:
                    raise ValueError("Missing keys in JSON output.")
            return result
        except (error.HTTPError, error.URLError, ValueError, json.JSONDecodeError) as e:
            if attempt == MAX_RETRIES - 1:
                raise
            sleep_s = min(2 ** attempt + random.random(), 30)
            print(f"Retry {attempt + 1} after error: {e}. Sleeping {sleep_s:.1f}s")
            time.sleep(sleep_s)


def main() -> None:
    load_dotenv_if_needed()
    rows = read_rows()
    start_index = get_resume_index()

    if start_index >= len(rows):
        print("Nothing to do. Output already complete.")
        return

    write_header_if_needed()
    print(f"Processing rows {start_index} to {len(rows) - 1}...")

    for start in range(start_index, len(rows), BATCH_SIZE):
        batch = rows[start : start + BATCH_SIZE]
        batch_rows = list(enumerate(batch, start=start))
        result = translate_batch(batch_rows)

        # Map by index to preserve original order
        by_index = {item["index"]: item for item in result}
        with open(OUTPUT_CSV, "a", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            for idx, row in batch_rows:
                item = by_index[idx]
                writer.writerow(
                    [
                        row.get("Level", "").strip(),
                        row.get("List", "").strip(),
                        str(item.get("word1", "")).strip(),
                        str(item.get("word2", "")).strip(),
                    ]
                )

        print(f"Wrote rows {start} to {min(start + BATCH_SIZE - 1, len(rows) - 1)}")

    print("Done. Output:", OUTPUT_CSV)


if __name__ == "__main__":
    main()
