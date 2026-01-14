import csv
import os

# Check the extracted CSV from the APK
csv_path = 'build/apk_extracted/assets/flutter_assets/assets/sets/combined_words_ukr.csv'

if not os.path.exists(csv_path):
    print(f"ERROR: File not found: {csv_path}")
    exit(1)

with open(csv_path, encoding='utf-8') as f:
    data = list(csv.DictReader(f))

print(f'Total entries in APK CSV: {len(data)}')

b1_data = [row for row in data if row.get('Level') == 'B1']
print(f'B1 entries: {len(b1_data)}')

lists = sorted(set([row.get('List', '') for row in b1_data if row.get('List')]))
print(f'B1 lists ({len(lists)} total):')
print(lists)

# Check for B1L5
b1l5 = [row for row in b1_data if row.get('List') == 'B1L5']
b1l6 = [row for row in b1_data if row.get('List') == 'B1L6']
print(f'\nB1L5 entries: {len(b1l5)}')
print(f'B1L6 entries: {len(b1l6)}')

if b1l5:
    print(f'✓ B1L5 EXISTS in APK! First word: {b1l5[0]["Eng"]}')
else:
    print('✗ B1L5 MISSING in APK!')

# Check for gaps
import re
nums = []
for lst in lists:
    match = re.search(r'L(\d+)', lst)
    if match:
        nums.append(int(match.group(1)))

if nums:
    nums.sort()
    expected = list(range(1, max(nums) + 1))
    missing = [n for n in expected if n not in nums]
    if missing:
        print(f'\n⚠️  WARNING: Missing L{missing}')
    else:
        print(f'\n✓ No gaps! All lists from L1 to L{max(nums)} are present')
