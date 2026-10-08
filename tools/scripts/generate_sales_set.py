import csv
import json
import os
import re
import sys
import time
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()

# Check for API key
api_key = os.getenv("OPENAI_API_KEY")
if not api_key:
    print("Error: OPENAI_API_KEY is not set in .env file")
    sys.exit(1)

client = OpenAI(api_key=api_key, timeout=120.0)

EN_CSV_PATH = "assets/data/sets/en.csv"
UK_CSV_PATH = "assets/data/sets/uk.csv"

# Load existing words to avoid duplicates
existing_words = set()
try:
    with open(EN_CSV_PATH, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)
        for row in reader:
            if len(row) >= 3:
                existing_words.add(row[2].lower().strip())
    print(f"Loaded {len(existing_words)} existing words to avoid duplicates.")
except Exception as e:
    print(f"Warning: Could not load existing words: {e}")

CATEGORIES = [
    {
        "name": "SalesL1",
        "description": "B2B Sales process, negotiations, pitching, closing, deals, contracting, financial terms (e.g., procurement, commission, rebate, leverage, value proposition, concessions, high-ticket sales)."
    },
    {
        "name": "SalesL2",
        "description": "Prefabricated modular construction, architecture, structural specifications, building codes, zoning, foundations, utilities, Scandinavia-inspired styling, footprint (e.g., modularity, durability, insulation, envelope, zoning, permit, layout, logistics)."
    },
    {
        "name": "SalesL3",
        "description": "Resort development, RV parks, campgrounds, hospitality industry terms, occupancy, land development, site planning, amenities, glamping, tourism, customer experience (e.g., lodging, feasibility, yield, infrastructure, vacancy, occupancy, peak season)."
    },
    {
        "name": "SalesL4",
        "description": "High-level corporate business English, executive communication, operations, scaling, management, strategic terminology (e.g., expedite, optimize, forecast, mitigate, streamline, capitalize, ROI, cost-benefit analysis)."
    },
    {
        "name": "SalesL5",
        "description": "Customer relations, CRM, client onboarding, objection handling, value selling, customer lifecycle, retention, feedback, quality assurance (e.g., rapport, referral, customer acquisition cost, objection, testimonial, criteria, consensus)."
    },
    {
        "name": "SalesL6",
        "description": "Common expressions/phrases used in US cold sales, cold outreach, and client communication. Must be 1 to 3 words long. Focus on lead nurturing, initial contact, establishing interest, booking meetings, follow-ups, and managing early objections (e.g., touch base, circle back, pain point, decision maker, warm intro, follow up, discovery call, value prop)."
    }
]

def clean_word(w):
    return w.lower().strip().replace('"', "").replace("'", "")

def generate_batch(category_desc, needed_count, blacklist):
    blacklist_str = ", ".join(list(blacklist)[:150]) # limit blacklist size in prompt
    prompt = f"""You are a professional lexicographer compiling a premium English-Ukrainian vocabulary set for sales professionals in the US tiny house and resort construction industries.

Generate a list of {needed_count} unique, high-quality, professional English vocabulary words/phrases, their brief English synonyms, and natural Ukrainian translations.

Theme/Category: {category_desc}

Requirements:
1. Target level: B1, B2, C1, C2. STRICTLY NO A1 or A2 level words (like "house", "build", "sell", "price", "customer", "camp", "buy", "good", "new", "time").
2. The English word/phrase should be a term or expression highly relevant to the category.
3. The synonym must be a brief (1-3 words) English synonym or short explanation.
4. The Ukrainian translation must be natural, professional, grammatically correct, and standard business/technical Ukrainian.
5. Do NOT include any of the following blacklisted/already used words: {blacklist_str}

Return your response ONLY as a valid JSON array of objects with the exact keys: "word", "synonym", "translation".
Example:
[
  {{"word": "concession", "synonym": "compromise", "translation": "поступка"}},
  {{"word": "modularity", "synonym": "segmented design", "translation": "модульність"}}
]
Do not wrap it in markdown block tags, just return the raw JSON.
"""
    try:
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[{"role": "user", "content": prompt}],
            temperature=0.7
        )
        content = response.choices[0].message.content.strip()
        # Remove markdown wrapper if present
        if content.startswith("```json"):
            content = content[7:]
        if content.endswith("```"):
            content = content[:-3]
        content = content.strip()
        
        return json.loads(content)
    except Exception as e:
        print(f"API Error: {e}", flush=True)
        time.sleep(2)
        return []

def main():
    print("Starting sales vocabulary generation...", flush=True)
    
    # Load existing list names from the CSV file to skip them if already generated
    existing_lists = set()
    try:
        with open(EN_CSV_PATH, "r", encoding="utf-8") as f:
            reader = csv.reader(f)
            for row in reader:
                if len(row) >= 2 and row[0] == "Sales":
                    existing_lists.add(row[1])
        print(f"Already generated lists in CSV: {existing_lists}", flush=True)
    except Exception as e:
        print(f"Could not check existing sales lists: {e}", flush=True)

    sales_generated_words = set()
    
    for cat in CATEGORIES:
        list_name = cat["name"]
        desc = cat["description"]
        
        if list_name in existing_lists:
            print(f"\nSublist {list_name} already exists in CSV. Skipping.", flush=True)
            continue
            
        print(f"\nGenerating words for sublist: {list_name}...", flush=True)
        
        sublist_words = []
        attempts = 0
        while len(sublist_words) < 200 and attempts < 15:
            attempts += 1
            needed = 200 - len(sublist_words)
            # Ask for slightly more to compensate for duplicates
            ask_count = min(needed + 20, 200)
            print(f"  Attempt {attempts}: Requesting {ask_count} words (collected so far: {len(sublist_words)}/200)...", flush=True)
            
            batch = generate_batch(desc, ask_count, sales_generated_words)
            if not batch:
                print("  Received empty batch, retrying...", flush=True)
                continue
            
            added_in_batch = 0
            for item in batch:
                word = item.get("word", "").strip()
                synonym = item.get("synonym", "").strip()
                translation = item.get("translation", "").strip()
                
                if not word or not synonym or not translation:
                    continue
                
                cleaned = clean_word(word)
                if cleaned in sales_generated_words:
                    continue
                    
                sales_generated_words.add(cleaned)
                sublist_words.append((word, synonym, translation))
                added_in_batch += 1
                
                if len(sublist_words) >= 200:
                    break
            
            print(f"  Added {added_in_batch} unique words in this batch.", flush=True)
        
        if len(sublist_words) < 200:
            print(f"Warning: Could only generate {len(sublist_words)} words for {list_name} after 15 attempts. Proceeding with what we have.", flush=True)
            
        if not sublist_words:
            print(f"Error: Generated 0 words for {list_name}. Skipping write.", flush=True)
            continue
            
        # Write to CSV files immediately for this list
        with open(EN_CSV_PATH, "a", encoding="utf-8", newline="") as en_f, \
             open(UK_CSV_PATH, "a", encoding="utf-8", newline="") as uk_f:
            en_writer = csv.writer(en_f)
            uk_writer = csv.writer(uk_f)
            
            for word, synonym, translation in sublist_words:
                en_writer.writerow(["Sales", list_name, word, synonym])
                uk_writer.writerow(["Sales", list_name, translation, ""])
        
        print(f"Successfully wrote {len(sublist_words)} words for {list_name} to CSV files.", flush=True)
        
    print("\nGeneration completed successfully!", flush=True)

if __name__ == "__main__":
    main()
