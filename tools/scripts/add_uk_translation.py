import csv

SRC = r'assets/data/sets/combined_words.csv'
DICT = r'assets/en_uk_dictionary.csv'
DST = r'assets/data/sets/combined_words_with_uk.csv'

# Load dictionary
en2uk = {}
with open(DICT, encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        en = row['en'].strip().lower()
        uk = row['uk'].strip()
        en2uk[en] = uk

# Process combined_words.csv
with open(SRC, encoding='utf-8') as fin, open(DST, 'w', encoding='utf-8', newline='') as fout:
    reader = csv.DictReader(fin)
    fieldnames = reader.fieldnames
    writer = csv.DictWriter(fout, fieldnames=fieldnames)
    writer.writeheader()
    for row in reader:
        en_word = row.get('Eng', row.get('word', '')).strip().lower()
        uk_key = 'Ukr' if 'Ukr' in row else 'uk'
        row[uk_key] = en2uk.get(en_word, row.get(uk_key, ''))
        writer.writerow(row)

print(f"Done! Output: {DST}")
