import csv
import os

INPUT_FILE = r'C:\Users\Alex\english_words_app\assets\sets\combined_words_span.csv'
OUTPUT_FILE = r'C:\Users\Alex\english_words_app\assets\sets\combined_words_span_sorted.csv'

def main():
    if not os.path.exists(INPUT_FILE):
        print(f"File not found: {INPUT_FILE}")
        return

    print("Reading CSV...")
    with open(INPUT_FILE, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = list(reader)

    print(f"Read {len(rows)} rows. Sorting...")
    
    # Sort by Column 0 (Level) then Column 1 (List)
    # Assuming these are strings like "A1", "A1L1". 
    # Standard string sort works well enough for A1, A2, B1...
    rows.sort(key=lambda x: (x[0], x[1]))

    print("Writing sorted CSV...")
    with open(OUTPUT_FILE, 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)

    print(f"Done! Saved to {OUTPUT_FILE}")
    
    # Replace the original?
    # os.replace(OUTPUT_FILE, INPUT_FILE)
    # print("Replaced original file.")

if __name__ == "__main__":
    main()
