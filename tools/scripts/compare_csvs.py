import csv

# Check the mysterious combined_words.csv file
print("=== Checking combined_words.csv ===")
try:
    with open('assets/data/sets/combined_words.csv', encoding='utf-8') as f:
        data = list(csv.DictReader(f))
    
    print(f'Total entries: {len(data)}')
    
    b1_data = [row for row in data if row.get('Level') == 'B1']
    print(f'B1 entries: {len(b1_data)}')
    
    lists = sorted(set([row.get('List', '') for row in b1_data if row.get('List')]))
    print(f'B1 lists: {lists}')
    
    # Check for B1L5
    b1l5 = [row for row in b1_data if row.get('List') == 'B1L5']
    print(f'B1L5 entries: {len(b1l5)}')
    
except Exception as e:
    print(f'Error: {e}')

print("\n=== Checking combined_words_ukr.csv ===")
with open('assets/data/sets/combined_words_ukr.csv', encoding='utf-8') as f:
    data = list(csv.DictReader(f))

print(f'Total entries: {len(data)}')

b1_data = [row for row in data if row.get('Level') == 'B1']
print(f'B1 entries: {len(b1_data)}')

lists = sorted(set([row.get('List', '') for row in b1_data if row.get('List')]))
print(f'B1 lists: {lists}')

# Check for B1L5
b1l5 = [row for row in b1_data if row.get('List') == 'B1L5']
print(f'B1L5 entries: {len(b1l5)}')
