import csv
import re

def is_portuguese_spanish(text):
    # Common Portuguese/Spanish words found in the wrecked file
    keywords = ['resultado', 'opcion', 'opção', 'eliminacion', 'eliminación', 'gritar', 'juez', 'atleta', 'inversor', 'experiencia']
    for k in keywords:
        if k in text.lower():
            return True
    return False

def check_ukr_file(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader)
        
        first_bad_row = None
        for i, row in enumerate(reader, start=2):
            if len(row) < 8:
                print(f"Row {i}: Incomplete ({len(row)} columns)")
                if first_bad_row is None: first_bad_row = i
                continue
                
            level, list_name, eng, ukr, ex1, ex2, ex3, ex4 = row
            
            # Check for empty fields
            if not ukr or not ex1 or not ex2 or not ex3 or not ex4:
                print(f"Row {i}: Empty fields for '{eng}'")
                if first_bad_row is None: first_bad_row = i
                continue
            
            # Check for same-as-english translation
            if ukr.lower() == eng.lower() and len(eng) > 3:
                print(f"Row {i}: Translation matches English for '{eng}'")
                if first_bad_row is None: first_bad_row = i
                continue
                
            # Check for Portuguese/Spanish leakage
            if is_portuguese_spanish(ukr) or is_portuguese_spanish(ex3) or is_portuguese_spanish(ex4):
                print(f"Row {i}: Portuguese/Spanish detected in '{eng}': {ukr}, {ex3}, {ex4}")
                if first_bad_row is None: first_bad_row = i
                continue
        
        if first_bad_row:
            print(f"\nFirst bad row detected at line: {first_bad_row}")
        else:
            print("\nNo bad rows detected!")

if __name__ == "__main__":
    check_ukr_file('assets/data/sets/combined_words_ukr.csv')
