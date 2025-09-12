input_file = "assets/sets/all_sets.csv"
output_file = "assets/sets/all_lists.csv"

with open(input_file, "r", encoding="utf-8") as f:
    content = f.read()

content = content.replace("set", "list")  # lowercase to match your CSV

with open(output_file, "w", encoding="utf-8") as f:
    f.write(content)

print("Done! Saved as", output_file)