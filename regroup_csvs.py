import csv
import os

SOURCE_REF = 'assets/sets/combined_words.csv'
SPAN_FILE = 'assets/sets/combined_words_span.csv'
UKR_FILE = 'assets/sets/combined_words_ukr.csv'

def regroup_file(target_file):
    if not os.path.exists(target_file):
        print(f"Skipping {target_file} (not found)")
        return

    print(f"Regrouping {target_file}...")
    
    # Load all data from target file into a map of queues to handle duplicates
    word_to_data_queues = {}
    fieldnames = []
    with open(target_file, 'r', encoding='utf-8') as f:
        # We use a standard reader first to handle potentially malformed rows
        # then convert to dict manually to avoid the "None" key error.
        reader = csv.reader(f)
        header = next(reader)
        fieldnames = header
        for row in reader:
            # Pad or truncate row to match header length
            clean_row = row[:len(header)] + [''] * (len(header) - len(row))
            row_dict = dict(zip(header, clean_row))
            word = row_dict['Eng'].lower().strip()
            if word not in word_to_data_queues:
                word_to_data_queues[word] = []
            word_to_data_queues[word].append(row_dict)

    new_rows = []
    missing_count = 0
    
    # Iterate through reference file to define the new order and grouping
    with open(SOURCE_REF, 'r', encoding='utf-8') as f:
        ref_reader = csv.DictReader(f)
        for ref_row in ref_reader:
            word = ref_row['Eng'].lower().strip()
            
            if word in word_to_data_queues and word_to_data_queues[word]:
                # Take the next available entry for this word
                match_data = word_to_data_queues[word].pop(0)
                
                # Update Level and List from reference
                match_data['Level'] = ref_row['Level']
                match_data['List'] = ref_row['List']
                new_rows.append(match_data)
            else:
                missing_count += 1
                # Create a placeholder row
                placeholder = {k: '' for k in fieldnames}
                placeholder['Level'] = ref_row['Level']
                placeholder['List'] = ref_row['List']
                placeholder['Eng'] = ref_row['Eng']
                new_rows.append(placeholder)

    # Write back to file
    with open(target_file, 'w', encoding='utf-8', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(new_rows)
    
    print(f"Done regrouping {target_file}. Words missing in target: {missing_count}")

def main():
    # Make backups
    import shutil
    for f in [SPAN_FILE, UKR_FILE]:
        if os.path.exists(f):
            shutil.copy2(f, f + '.pregroup_bak')
            print(f"Backed up {f} to {f}.pregroup_bak")

    regroup_file(SPAN_FILE)
    regroup_file(UKR_FILE)

if __name__ == '__main__':
    main()
