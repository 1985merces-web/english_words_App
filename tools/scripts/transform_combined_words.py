import csv
import random
from deep_translator import GoogleTranslator

INPUT_FILE = 'assets/data/sets/combined_words.csv'
OUTPUT_FILE = 'new_combined_words.csv'

translator = GoogleTranslator(source='en', target='pt')

def generate_examples(word):
    templates = [
        f'{word} example', f'{word} usage', f'{word} phrase', f'{word} meaning',
        f'{word} context', f'{word} form', f'{word} type', f'{word} case',
        f'{word} idea', f'{word} way'
    ]
    random.shuffle(templates)
    return templates[:2]

with open(INPUT_FILE, newline='', encoding='utf-8') as infile, \
     open(OUTPUT_FILE, 'w', newline='', encoding='utf-8') as outfile:
    
    reader = csv.DictReader(infile)
    fieldnames = reader.fieldnames
    writer = csv.DictWriter(outfile, fieldnames=fieldnames)
    writer.writeheader()

    for row in reader:
        eng = row['Eng']
        try:
            row['Ukr'] = translator.translate(eng)
            ex1_en, ex2_en = generate_examples(eng)
            row['Example1'] = translator.translate(ex1_en)
            row['Example2'] = translator.translate(ex2_en)
        except Exception as e:
            row['Ukr'] = ''
            row['Example1'] = ''
            row['Example2'] = ''
        writer.writerow(row)