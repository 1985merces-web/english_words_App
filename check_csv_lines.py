import csv

def check_file(path):
    print(f"Checking {path}...")
    try:
        with open(path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            print(f"  Physical line count: {len(lines)}")
        
        with open(path, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            row_count = 0
            for i, row in enumerate(reader):
                row_count += 1
            print(f"  CSV row count: {row_count}")
    except Exception as e:
        print(f"  Error: {e}")

check_file('assets/sets/combined_words.csv')
check_file('assets/sets/combined_words_span.csv')
check_file('assets/sets/combined_words_ukr.csv')
