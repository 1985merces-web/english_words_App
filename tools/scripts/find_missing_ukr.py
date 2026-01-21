import csv

def find_missing_rows(source_file, target_file):
    source_words = []
    with open(source_file, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader)
        for row in reader:
            source_words.append((row[0], row[1], row[2])) # (Level, List, Eng)
            
    target_words = set()
    with open(target_file, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader)
        for row in reader:
            target_words.add((row[0], row[1], row[2]))
            
    missing = []
    for row in source_words:
        if row not in target_words:
            missing.append(row)
            
    return missing

if __name__ == "__main__":
    missing = find_missing_rows('assets/data/sets/combined_words.csv', 'assets/data/sets/combined_words_ukr.csv')
    print(f"Total missing rows: {len(missing)}")
    if missing:
        print("First 10 missing:")
        for m in missing[:10]:
            print(m)
        
        # Save missing rows to a temp file for processing
        source_data = {}
        with open('assets/data/sets/combined_words.csv', 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            header = next(reader)
            for row in reader:
                source_data[(row[0], row[1], row[2])] = row
                
        with open('missing_ukr_rows.csv', 'w', encoding='utf-8', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(header)
            for m in missing:
                writer.writerow(source_data[m])
