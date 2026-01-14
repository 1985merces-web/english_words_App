import csv
from collections import Counter

csv_path = 'assets/sets/combined_words_ukr.csv'
print(f"Analyzing {csv_path}...")

with open(csv_path, 'r', encoding='utf-8') as f:
    reader = csv.reader(f)
    header = next(reader)
    print(f"Header: {header} (length: {len(header)})")
    
    malformed_rows = []
    level_counts = Counter()
    total_rows = 0
    
    for i, row in enumerate(reader):
        num = i + 2 # 1-indexed + header
        total_rows += 1
        
        if len(row) != len(header):
            malformed_rows.append((num, len(row), row))
            
        level = row[0] if len(row) > 0 else "EMPTY"
        level_counts[level] += 1
        
    print(f"\nTotal data rows: {total_rows}")
    print("\nLevel matches (A1, A2, B1, B2, C1, C2):")
    valid_levels = {'A1', 'A2', 'B1', 'B2', 'C1', 'C2'}
    for lvl, count in level_counts.items():
        status = "✓" if lvl in valid_levels else "✗ MALFORMED"
        print(f"  {lvl}: {count} {status}")
        
    if malformed_rows:
        print(f"\nFound {len(malformed_rows)} rows with wrong column count!")
        print("First 5 malformed rows:")
        for num, length, content in malformed_rows[:5]:
            print(f"  Line {num}: Expected {len(header)} cols, got {length}. Row snippet: {str(content)[:100]}")
    else:
        print("\n✓ All rows have the correct number of columns.")

# Check for invisible characters in level names
print("\nChecking for invisible characters in level names:")
for lvl in level_counts.keys():
    if lvl in valid_levels:
        repr_lvl = repr(lvl)
        if repr_lvl != f"'{lvl}'":
            print(f"  WARNING: Level {lvl} has hidden characters: {repr_lvl}")

# Check for rows with level == ""
empty_level_rows = [i for i, row in enumerate(open(csv_path, encoding='utf-8')) if row.startswith(',')]
if empty_level_rows:
    print(f"\nFound {len(empty_level_rows)} rows starting with a comma (empty level)!")
    print(f"Lines: {empty_level_rows[:10]}")
