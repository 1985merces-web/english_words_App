import csv

with open('assets/data/sets/combined_words_ukr.csv', encoding='utf-8') as f:
    data = list(csv.DictReader(f))

b1_data = [row for row in data if row['Level'] == 'B1']
print(f'Total B1 entries: {len(b1_data)}')

lists = sorted(set([row['List'] for row in b1_data]))
print(f'B1 lists ({len(lists)} total): {lists}')

print('\nFirst 10 B1 entries:')
for row in b1_data[:10]:
    print(f"{row['Level']},{row['List']},{row['Eng']}")

print('\nSearching for B1L5 and B1L6:')
b1l5 = [row for row in b1_data if row['List'] == 'B1L5']
b1l6 = [row for row in b1_data if row['List'] == 'B1L6']
print(f'B1L5 entries: {len(b1l5)}')
print(f'B1L6 entries: {len(b1l6)}')

if b1l5:
    print(f'First B1L5 word: {b1l5[0]["Eng"]}')
if b1l6:
    print(f'First B1L6 word: {b1l6[0]["Eng"]}')
