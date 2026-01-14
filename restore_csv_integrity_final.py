import csv
import os
import re

SPAN_REF = 'assets/sets/combined_words_span.csv'
UKR_INPUT = 'assets/sets/combined_words_ukr.csv'
UKR_OUTPUT = 'assets/sets/combined_words_ukr.csv' # Overwrite original after backup

def level_index(lvl):
    order = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2']
    try:
        return order.index(lvl.upper())
    except ValueError:
        return 999

def main():
    if not os.path.exists(SPAN_REF):
        print(f"Error: {SPAN_REF} not found.")
        return

    # Backup original
    if os.path.exists(UKR_INPUT):
        os.rename(UKR_INPUT, UKR_INPUT + '.bak')
        print(f"Backed up {UKR_INPUT} to {UKR_INPUT}.bak")

    print(f"Loading reference from {SPAN_REF}...")
    # Reference is 10k+ rows. Level/List distribution is source of truth.
    ref_rows = []
    with open(SPAN_REF, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            ref_rows.append(row)

    print(f"Loading Ukrainian translations from {UKR_INPUT}.bak...")
    # Map words to their best Ukrainian data
    ukr_dict = {}
    with open(UKR_INPUT + '.bak', 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            word = row['Eng'].lower().strip()
            ukr_dict[word] = row

    print("Restoring and Splitting Lists...")
    restored_rows = []
    
    # We will split lists so they have max 25 words each.
    # We group ref_rows by Level first to ensure sequential re-listing.
    by_level = {}
    for row in ref_rows:
        lvl = row['Level']
        if lvl not in by_level: by_level[lvl] = []
        by_level[lvl].append(row)

    level_order = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2']
    
    WORDS_PER_LIST = 25

    for lvl in level_order:
        if lvl not in by_level: continue
        
        words = by_level[lvl]
        total = len(words)
        
        for i, ref_row in enumerate(words):
            word = ref_row['Eng'].lower().strip()
            
            # Find closest match in Ukrainian dict
            u_row = ukr_dict.get(word)
            
            # Fallback for minor changes (e.g. 'youth' matches 'youthful' if no exact match?)
            # Actually, let's keep it simple for now: if no match, 
            # try finding it in keys if key starts with word
            if not u_row:
                for k in ukr_dict:
                    if k.startswith(word) or word.startswith(k):
                        u_row = ukr_dict[k]
                        break

            # Re-calculating List name: Level + L + (index // 25 + 1)
            # This ensures sequence: A1L1, A1L2, A1L3...
            list_num = (i // WORDS_PER_LIST) + 1
            new_list_name = f"{lvl}L{list_num}"
            
            # Handle the B1L5 gap fix automatically by just re-listing everything sequential
            
            new_row = {
                'Level': lvl,
                'List': new_list_name,
                'Eng': ref_row['Eng'],
                'Ukr': u_row['Ukr'] if u_row else ref_row['Eng'], # Fallback to Eng if missing
                'Example1': u_row['Example1'] if u_row else ref_row['Example1'],
                'Example2': u_row['Example2'] if u_row else ref_row['Example2'],
                'Example3': u_row['Example3'] if u_row else ref_row['Example3'],
                'Example4': u_row['Example4'] if u_row else ref_row['Example4']
            }
            restored_rows.append(new_row)

    print(f"Writing {len(restored_rows)} restored rows to {UKR_OUTPUT}...")
    fieldnames = ['Level', 'List', 'Eng', 'Ukr', 'Example1', 'Example2', 'Example3', 'Example4']
    with open(UKR_OUTPUT, 'w', encoding='utf-8', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(restored_rows)

    print("\nDONE!")
    print(f"Restored file has {len(restored_rows)} rows.")
    # Show summary of list counts
    final_counts = {}
    for r in restored_rows:
        key = (r['Level'], r['List'])
        final_counts[key] = final_counts.get(key, 0) + 1
    
    print(f"Levels produced: {sorted(list(set(r['Level'] for r in restored_rows)), key=level_index)}")
    print(f"Total lists: {len(final_counts)}")
    # Print A1 counts
    a1_lists = [k for k in final_counts if k[0] == 'A1']
    print(f"A1 lists: {len(a1_lists)} (max words per list: {max(final_counts.values())})")

if __name__ == '__main__':
    main()
