import csv
import os
import re

SPAN_REF = 'assets/data/sets/combined_words_span.csv'
UKR_INPUT = 'assets/data/sets/combined_words_ukr.csv'
UKR_OUTPUT = 'assets/data/sets/combined_words_ukr_restored.csv'

def extract_list_num(s):
    match = re.search(r'L(\d+)', s, re.I)
    return int(match.group(1)) if match else 999

def level_index(lvl):
    order = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2']
    try:
        return order.index(lvl.upper())
    except ValueError:
        return 999

def main():
    print(f"Loading reference mappings from {SPAN_REF}...")
    # Reference map: {english_word.lower(): (Level, List)}
    ref_map = {}
    with open(SPAN_REF, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            word = row['Eng'].lower().strip()
            # If word appears multiple times, we'll take the first mapping seen
            if word not in ref_map:
                ref_map[word] = (row['Level'], row['List'])

    print(f"Loading Ukrainian data from {UKR_INPUT}...")
    # Ukr data map: {english_word.lower(): row_data}
    ukr_data = {}
    with open(UKR_INPUT, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            word = row['Eng'].lower().strip()
            ukr_data[word] = row

    print("Restoring mappings...")
    restored_rows = []
    missing_words = []
    
    # Iterate over EVERY word exactly as it appears in the reference (Spanish) file
    # to maintain total integrity and order base.
    with open(SPAN_REF, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            word = row['Eng'].lower().strip()
            
            if word in ukr_data:
                u_row = ukr_data[word]
                # Use reference Level and List, but Ukrainian translations and examples
                new_row = {
                    'Level': row['Level'],
                    'List': row['List'],
                    'Eng': u_row['Eng'],
                    'Ukr': u_row['Ukr'],
                    'Example1': u_row['Example1'],
                    'Example2': u_row['Example2'],
                    'Example3': u_row['Example3'],
                    'Example4': u_row['Example4']
                }
                restored_rows.append(new_row)
            else:
                missing_words.append(row['Eng'])
                # If Ukrainian translation is missing, we could flag it or use original
                # but for simplicity let's just use original columns if it exists
                # In this project, all words should have been processed.
    
    print(f"Total restored rows: {len(restored_rows)}")
    if missing_words:
        print(f"WARNING: {len(missing_words)} words from Spanish reference were not found in Ukrainian file.")
        print(f"Missing (first 10): {missing_words[:10]}")

    # Special handling for B1 renumbering (the L5 fix)
    # The Spanish reference HAS the original B1L6 -> B1L14.
    # We want to re-apply the B1L5 gap closure.
    print("Re-applying B1 renumbering (L6-L14 -> L5-L13)...")
    for row in restored_rows:
        if row['Level'] == 'B1' and row['List'].startswith('B1L'):
            try:
                num = int(row['List'][3:])
                if num >= 6:
                    row['List'] = f"B1L{num-1}"
            except ValueError:
                pass

    # Sorting
    print("Sorting rows by Level and List...")
    restored_rows.sort(key=lambda x: (level_index(x['Level']), extract_list_num(x['List'])))

    print(f"Writing restored CSV to {UKR_OUTPUT}...")
    fieldnames = ['Level', 'List', 'Eng', 'Ukr', 'Example1', 'Example2', 'Example3', 'Example4']
    with open(UKR_OUTPUT, 'w', encoding='utf-8', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(restored_rows)

    print("\nDONE! Integrity restored.")
    print(f"Please verify {UKR_OUTPUT} and then replace the original.")

if __name__ == '__main__':
    main()
