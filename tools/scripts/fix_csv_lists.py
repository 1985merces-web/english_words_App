#!/usr/bin/env python3
"""
Fix CSV list numbering by renumbering B1L6->B1L5, B1L7->B1L6, etc.
This closes the gap where B1L5 is missing.
"""

import csv
import shutil
from datetime import datetime

INPUT_FILE = 'assets/data/sets/combined_words_ukr.csv'
OUTPUT_FILE = 'assets/data/sets/combined_words_ukr_fixed.csv'
BACKUP_FILE = f'assets/data/sets/combined_words_ukr_backup_{datetime.now().strftime("%Y%m%d_%H%M%S")}.csv'

def main():
    # Create backup
    print(f"Creating backup: {BACKUP_FILE}")
    shutil.copy2(INPUT_FILE, BACKUP_FILE)
    
    # Read CSV
    print(f"Reading {INPUT_FILE}...")
    with open(INPUT_FILE, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        rows = list(reader)
    
    print(f"Total rows: {len(rows)}")
    print(f"Fieldnames: {fieldnames}")
    
    # Clean rows - remove any None keys
    cleaned_rows = []
    for row in rows:
        cleaned_row = {k: v for k, v in row.items() if k is not None}
        cleaned_rows.append(cleaned_row)
    
    # Renumber B1 lists
    changes = 0
    for row in cleaned_rows:
        if row.get('Level') == 'B1':
            list_name = row.get('List', '')
            # Extract number from B1LX format
            if list_name.startswith('B1L'):
                try:
                    num = int(list_name[3:])
                    if num >= 6:
                        # Renumber: B1L6->B1L5, B1L7->B1L6, etc.
                        new_num = num - 1
                        new_list_name = f'B1L{new_num}'
                        row['List'] = new_list_name
                        changes += 1
                except ValueError:
                    pass
    
    print(f"Renumbered {changes} B1 list entries")
    
    # Write fixed CSV
    print(f"Writing fixed CSV to {OUTPUT_FILE}...")
    # Filter fieldnames to remove None
    clean_fieldnames = [f for f in fieldnames if f is not None]
    with open(OUTPUT_FILE, 'w', encoding='utf-8', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=clean_fieldnames)
        writer.writeheader()
        writer.writerows(cleaned_rows)
    
    print("Done! Fixed CSV written to:", OUTPUT_FILE)
    print("\nTo apply the fix, run:")
    print(f"  move {OUTPUT_FILE} {INPUT_FILE}")
    
    # Verify the fix
    print("\nVerifying fix...")
    with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
        data = list(csv.DictReader(f))
    
    b1_lists = sorted(set([row['List'] for row in data if row['Level'] == 'B1']))
    print(f"B1 lists after fix: {b1_lists}")
    
    # Check for gaps
    import re
    nums = []
    for lst in b1_lists:
        match = re.search(r'L(\d+)', lst)
        if match:
            nums.append(int(match.group(1)))
    
    if nums:
        nums.sort()
        expected = list(range(1, max(nums) + 1))
        missing = [n for n in expected if n not in nums]
        if missing:
            print(f"⚠️  WARNING: Still missing L{missing}")
        else:
            print("✓ No gaps found in B1 lists!")

if __name__ == '__main__':
    main()
