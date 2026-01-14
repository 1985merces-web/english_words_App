import csv
from collections import Counter

csv_path = 'assets/sets/combined_words_ukr.csv'
print(f"Checking consistency in {csv_path}...")

with open(csv_path, 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    
    level_list_mismatch = [] # Rows where List name doesn't contain the Level name
    list_format_counts = Counter()
    
    for i, row in enumerate(reader):
        lvl = row.get('Level', '')
        lst = row.get('List', '')
        
        # Check if List name starts with Level (e.g. A1L1 should be in A1)
        if not lst.upper().startswith(lvl.upper()):
            level_list_mismatch.append((i+2, lvl, lst))
            
        # Analyze list format
        if 'L' in lst.upper():
            list_format_counts['HAS_L'] += 1
        else:
            list_format_counts['NO_L'] += 1
            
    print(f"\nTotal rows checked: {i+1}")
    print(f"Level/List mismatches: {len(level_list_mismatch)}")
    
    if level_list_mismatch:
        print("\nFirst 10 mismatches:")
        for line, lvl, lst in level_list_mismatch[:10]:
            print(f"  Line {line}: Level={lvl}, List={lst}")
            
    print("\nList format counts:")
    for fmt, count in list_format_counts.items():
        print(f"  {fmt}: {count}")

# Check for duplicate words in different levels
print("\nChecking for word duplication across levels...")
word_levels = {}
duplicates = []
with open(csv_path, 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        word = row.get('Eng', '').lower().strip()
        lvl = row.get('Level', '')
        if word in word_levels and word_levels[word] != lvl:
            duplicates.append((word, word_levels[word], lvl))
        word_levels[word] = lvl

print(f"Words found in multiple levels: {len(duplicates)}")
if duplicates:
    print("Example duplicates:")
    for word, l1, l2 in duplicates[:5]:
        print(f"  '{word}': {l1} and {l2}")
