import csv

with open('assets/data/sets/combined_words_ukr.csv', encoding='utf-8') as f:
    data = list(csv.DictReader(f))

print(f'Total rows: {len(data)}')

# Group by level
levels = {}
for row in data:
    level = row['Level']
    list_name = row['List']
    if level not in levels:
        levels[level] = set()
    levels[level].add(list_name)

# Print each level
for level in sorted(levels.keys()):
    lists = levels[level]
    # Sort numerically
    def extract_num(s):
        import re
        match = re.search(r'L(\d+)', s)
        return int(match.group(1)) if match else 0
    
    sorted_lists = sorted(lists, key=lambda x: (x.split('L')[0], extract_num(x)))
    print(f'\n{level}: {len(sorted_lists)} lists')
    print(f'  Lists: {sorted_lists}')
    
    # Check for gaps
    nums = [extract_num(l) for l in sorted_lists]
    if nums:
        expected = list(range(1, max(nums) + 1))
        missing = [n for n in expected if n not in nums]
        if missing:
            print(f'  ⚠️  MISSING: L{missing}')
