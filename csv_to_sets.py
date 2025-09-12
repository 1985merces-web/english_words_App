# csv_to_sets.py
import csv
import json
import os
from collections import defaultdict

INPUT_CSV = 'assets/sets/all_sets.csv'
OUTPUT_DIR = 'assets/sets'

sets = defaultdict(list)

with open(INPUT_CSV, encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        sets[row['set']].append({'en': row['en'], 'uk': row['uk']})

for set_name, words in sets.items():
    with open(f'{OUTPUT_DIR}/{set_name}.json', 'w', encoding='utf-8') as f:
        json.dump(words, f, ensure_ascii=False, indent=2)

print('Done!')