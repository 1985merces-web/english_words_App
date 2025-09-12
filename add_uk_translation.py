import csv

SRC = r'assets/sets/all_lists.csv'
DICT = r'assets/en_uk_dictionary.csv'
DST = r'assets/sets/all_lists_with_uk.csv'

# Load dictionary
en2uk = {}
with open(DICT, encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        en = row['en'].strip().lower()
        uk = row['uk'].strip()
        en2uk[en] = uk

# Process all_lists.csv
with open(SRC, encoding='utf-8') as fin, open(DST, 'w', encoding='utf-8', newline='') as fout:
    reader = csv.DictReader(fin)
    fieldnames = reader.fieldnames[:3] + ['uk'] + reader.fieldnames[3:]
    writer = csv.DictWriter(fout, fieldnames=fieldnames)
    writer.writeheader()
    for row in reader:
        en_word = row['word'].strip().lower()
        row['uk'] = en2uk.get(en_word, '')
        writer.writerow(row)

print(f"Done! Output: {DST}")