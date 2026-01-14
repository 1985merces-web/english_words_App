import csv
import json
import os
import random
import time
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional
from urllib import error, request
from urllib.parse import urlencode


EN_CSV = os.getenv("EN_CSV", "assets/sets/en.csv")
PT_CSV = os.getenv("PT_CSV", "assets/sets/pt.csv")
MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
PROVIDER = os.getenv("PROVIDER", "auto").strip().lower()  # auto | openai | google

START_LINE = int(os.getenv("START_LINE", "5608"))  # 1-based, includes header
END_LINE = int(os.getenv("END_LINE", "10594"))  # 1-based, includes header

BATCH_SIZE = int(os.getenv("BATCH_SIZE", "25"))
MAX_RETRIES = int(os.getenv("MAX_RETRIES", "8"))
MIN_DELAY_S = float(os.getenv("MIN_DELAY_S", "1.0"))
GOOGLE_BATCH_LINES = int(os.getenv("GOOGLE_BATCH_LINES", "80"))


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


def read_csv_dict(path: str) -> List[Dict[str, str]]:
    with open(path, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        return list(reader)


def read_csv_rows(path: str) -> List[List[str]]:
    with open(path, "r", encoding="utf-8", newline="") as f:
        return list(csv.reader(f))


def write_csv_rows_atomic(path: str, rows: List[List[str]]) -> None:
    tmp_path = f"{path}.tmp"
    with open(tmp_path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerows(rows)
    os.replace(tmp_path, path)


@dataclass(frozen=True)
class Task:
    data_index: int  # 0-based within data rows
    needs_word1: bool
    needs_word2: bool
    word: str
    synonym: str


def _sleep_for_retry(e: Exception, attempt: int) -> None:
    retry_after: Optional[float] = None
    if isinstance(e, error.HTTPError):
        ra = e.headers.get("Retry-After")
        if ra:
            try:
                retry_after = float(ra)
            except ValueError:
                retry_after = None
    if retry_after is None:
        retry_after = min(2**attempt + random.random(), 60.0)
    time.sleep(retry_after)


def _read_http_error_body(e: error.HTTPError) -> str:
    try:
        return e.read().decode("utf-8", errors="replace")
    except Exception:
        return ""


def call_openai_translate(payload: List[Dict[str, str]]) -> List[Dict[str, str]]:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is not set (check .env).")

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
        f"Input JSON:\n{json.dumps(payload, ensure_ascii=False)}"
    )

    body = json.dumps(
        {
            "model": MODEL,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "temperature": 0.2,
        },
        ensure_ascii=False,
    ).encode("utf-8")

    req = request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=body,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        method="POST",
    )
    with request.urlopen(req, timeout=180) as resp:
        raw = resp.read().decode("utf-8")

    obj = json.loads(raw)
    content = obj["choices"][0]["message"]["content"].strip()

    start = content.find("[")
    end = content.rfind("]")
    if start == -1 or end == -1:
        raise ValueError("Model response is not a JSON array.")
    parsed = json.loads(content[start : end + 1])
    if not isinstance(parsed, list):
        raise ValueError("Model response JSON is not a list.")
    return parsed


def translate_google_lines(lines: List[str]) -> List[str]:
    joined = "\n".join(lines)
    url = "https://translate.googleapis.com/translate_a/single?" + urlencode(
        {"client": "gtx", "sl": "en", "tl": "pt", "dt": "t", "q": joined},
        encoding="utf-8",
    )

    with request.urlopen(url, timeout=120) as resp:
        raw = resp.read().decode("utf-8")
    obj = json.loads(raw)
    segments = obj[0]
    translated_text = "".join(seg[0] for seg in segments)
    out = translated_text.split("\n")
    if translated_text.endswith("\n"):
        out = out[:-1]
    return out


def translate_google_with_retry(lines: List[str]) -> List[str]:
    last_err: Optional[Exception] = None
    for attempt in range(MAX_RETRIES):
        try:
            out = translate_google_lines(lines)
            if len(out) != len(lines):
                raise ValueError(f"Line count mismatch: in={len(lines)} out={len(out)}")
            return out
        except (error.HTTPError, error.URLError, json.JSONDecodeError, ValueError) as e:
            last_err = e
            if attempt == MAX_RETRIES - 1:
                raise
            _sleep_for_retry(e, attempt)
    raise RuntimeError(f"Translation failed: {last_err}")


def batched(items: List[Task], batch_size: int) -> Iterable[List[Task]]:
    for i in range(0, len(items), batch_size):
        yield items[i : i + batch_size]


def main() -> None:
    if START_LINE < 2:
        raise SystemExit("START_LINE must be >= 2 (line 1 is header).")
    if END_LINE < START_LINE:
        raise SystemExit("END_LINE must be >= START_LINE.")

    load_dotenv_if_needed()

    en_rows = read_csv_dict(EN_CSV)
    pt_rows = read_csv_rows(PT_CSV)

    if not pt_rows or pt_rows[0] != ["Level", "List", "Word1", "Word2"]:
        raise SystemExit(f"Unexpected header in {PT_CSV}: {pt_rows[0] if pt_rows else None}")

    if len(pt_rows) != len(en_rows) + 1:
        raise SystemExit(
            f"Row count mismatch: {PT_CSV} has {len(pt_rows)-1} data rows, "
            f"but {EN_CSV} has {len(en_rows)} data rows."
        )

    start_idx = START_LINE - 2
    end_idx = END_LINE - 2
    if start_idx < 0 or end_idx >= len(en_rows):
        raise SystemExit(
            f"Requested range out of bounds. Data indices: 0..{len(en_rows)-1}, "
            f"requested {start_idx}..{end_idx}"
        )

    tasks: List[Task] = []
    for data_index in range(start_idx, end_idx + 1):
        en = en_rows[data_index]
        en_word = (en.get("Word") or "").strip()
        en_syn = (en.get("Synonym") or "").strip()

        pt_line = pt_rows[data_index + 1]
        pt_word1 = (pt_line[2] if len(pt_line) > 2 else "").strip()
        pt_word2 = (pt_line[3] if len(pt_line) > 3 else "").strip()

        needs_word1 = (not pt_word1) or (pt_word1.lower() == en_word.lower())
        needs_word2 = (not pt_word2) or (pt_word2.lower() == en_syn.lower())

        if needs_word1 or needs_word2:
            tasks.append(
                Task(
                    data_index=data_index,
                    needs_word1=needs_word1,
                    needs_word2=needs_word2,
                    word=en_word,
                    synonym=en_syn,
                )
            )

    if not tasks:
        print("Nothing to update in the requested range.")
        return

    provider = PROVIDER
    if provider not in {"auto", "openai", "google"}:
        raise SystemExit(f"Unsupported PROVIDER={PROVIDER!r}")

    if provider in {"auto", "openai"}:
        load_dotenv_if_needed()
        if not os.getenv("OPENAI_API_KEY"):
            provider = "google"
        else:
            # Probe once to avoid repeated quota failures.
            probe_payload = [{"index": tasks[0].data_index, "word": tasks[0].word, "synonym": tasks[0].synonym}]
            try:
                call_openai_translate(probe_payload)
            except error.HTTPError as e:
                body = _read_http_error_body(e)
                if e.code == 429 and "insufficient_quota" in body:
                    provider = "google"
                else:
                    raise

    if provider == "openai":
        print(
            f"Updating {len(tasks)} rows in {PT_CSV} via OpenAI (data indices {start_idx}..{end_idx}), "
            f"model={MODEL}, batch_size={BATCH_SIZE}"
        )

        updated = 0
        for batch in batched(tasks, BATCH_SIZE):
            payload = [{"index": t.data_index, "word": t.word, "synonym": t.synonym} for t in batch]

            for attempt in range(MAX_RETRIES):
                try:
                    result = call_openai_translate(payload)
                    if not isinstance(result, list) or len(result) != len(payload):
                        raise ValueError("JSON length mismatch.")

                    by_index = {}
                    for item in result:
                        if not isinstance(item, dict):
                            raise ValueError("JSON item is not an object.")
                        if "index" not in item or "word1" not in item or "word2" not in item:
                            raise ValueError("Missing keys in JSON output.")
                        by_index[int(item["index"])] = item

                    for task in batch:
                        item = by_index.get(task.data_index)
                        if not item:
                            raise ValueError(f"Missing result for index {task.data_index}")

                        line = pt_rows[task.data_index + 1]
                        while len(line) < 4:
                            line.append("")

                        if task.needs_word1:
                            line[2] = str(item.get("word1", "")).strip()
                        if task.needs_word2:
                            line[3] = str(item.get("word2", "")).strip()

                    updated += len(batch)
                    time.sleep(MIN_DELAY_S)
                    break
                except (error.HTTPError, error.URLError, ValueError, json.JSONDecodeError) as e:
                    if attempt == MAX_RETRIES - 1:
                        raise
                    _sleep_for_retry(e, attempt)

            if updated % 250 == 0:
                print(f"Progress: {updated}/{len(tasks)} updated...")
    else:
        print(
            f"Updating {len(tasks)} rows in {PT_CSV} via Google Translate (data indices {start_idx}..{end_idx}), "
            f"batch_lines={GOOGLE_BATCH_LINES}"
        )

        needed_texts: List[str] = []
        seen: set[str] = set()
        for t in tasks:
            if t.needs_word1 and t.word and t.word not in seen:
                seen.add(t.word)
                needed_texts.append(t.word)
            if t.needs_word2 and t.synonym and t.synonym not in seen:
                seen.add(t.synonym)
                needed_texts.append(t.synonym)

        translations: Dict[str, str] = {"": ""}
        done = 0
        for chunk_start in range(0, len(needed_texts), GOOGLE_BATCH_LINES):
            chunk = needed_texts[chunk_start : chunk_start + GOOGLE_BATCH_LINES]
            try:
                out = translate_google_with_retry(chunk)
            except Exception:
                # Fallback: translate one-by-one to isolate problematic items.
                out = []
                for text in chunk:
                    out.append(translate_google_with_retry([text])[0])
            for src, dst in zip(chunk, out):
                translations[src] = dst.strip()
            done += len(chunk)
            if done % 500 == 0 or done >= len(needed_texts):
                print(f"Progress: {done}/{len(needed_texts)} unique strings translated...")

        updated = 0
        for t in tasks:
            line = pt_rows[t.data_index + 1]
            while len(line) < 4:
                line.append("")
            if t.needs_word1:
                line[2] = translations.get(t.word, "").strip()
            if t.needs_word2:
                line[3] = translations.get(t.synonym, "").strip()
            updated += 1
            if updated % 1000 == 0:
                print(f"Progress: {updated}/{len(tasks)} rows updated...")

    write_csv_rows_atomic(PT_CSV, pt_rows)
    print("Done.")


if __name__ == "__main__":
    main()
