import pandas as pd

# Load the CSV file (new combined dataset)
df = pd.read_csv('assets/data/sets/combined_words.csv')

# Normalize column names so the existing logic can keep using legacy keys
column_mapping_to_internal = {
    'Level': 'level',
    'List': 'sublist',
    'Eng': 'word',
    'Ukr': 'uk',
    'Example1': 'example',
    'Example2': 'example2',
}
df.rename(
    columns={src: dst for src, dst in column_mapping_to_internal.items() if src in df.columns},
    inplace=True,
)

# --- Corrections Dictionary ---
# This dictionary contains all the corrections to be applied.
# 'uk' for UK translation, 'example' for the example sentence.
corrections = {
    # Words from 9400-9607
    "fairfield": {"uk": "ярмарок, виставковий майданчик", "example": "The annual fairfield attracts thousands of visitors."},
    "generous": {"uk": "щедрий, великодушний", "example": "She made a generous donation to the charity."},
    "fascinating": {"uk": "чарівний, захоплюючий", "example": "The museum has a fascinating collection of artifacts."},
    "subsequently": {"uk": "згодом, потім", "example": "He subsequently became a successful writer."},
    "suggesting": {"uk": "пропонуючи", "example": "Are you suggesting that I'm wrong?"},
    "promoted": {"uk": "просунутий, підвищений", "example": "She was promoted to senior manager."},
    "descending": {"uk": "спадний", "example": "The path was steeply descending."},
    "securely": {"uk": "надійно, безпечно", "example": "Make sure the ladder is securely positioned."},
    "fioricet": {"delete": True},
    "intranet": {"uk": "інтранет, внутрішня мережа", "example": "The documents are available on the company intranet."},
    "persistent": {"uk": "наполегливий, стійкий", "example": "He is a persistent salesman who doesn't take no for an answer."},
    "disputes": {"uk": "суперечки, спори", "example": "The two countries are in a dispute over the border."},
    "thriller": {"uk": "трилер, гостросюжетний фільм", "example": "It's a psychological thriller about a man who has lost his memory."},
    "fireplace": {"uk": "камін", "example": "They sat by the fireplace, drinking wine."},
    "planners": {"uk": "планувальники", "example": "The city planners are developing a new transport strategy."},
    "transparent": {"uk": "прозорий, очевидний", "example": "The water in the lake was so transparent you could see the bottom."},
    "endorsed": {"uk": "схвалений, підтриманий", "example": "The campaign was endorsed by several celebrities."},
    "yugoslavia": {"delete": True},
    "likelihood": {"uk": "ймовірність", "example": "There is a high likelihood of rain this afternoon."},
    "proprietary": {"uk": "власницький", "example": "This is proprietary software, and you need a license to use it."},
    "graduated": {"uk": "випустився", "example": "She graduated from university last year."},
    "commissions": {"uk": "комісії, комісійні", "example": "He earns a 10% commission on every sale."},
    "motivation": {"uk": "мотивація", "example": "He's a good student, but he lacks motivation."},
    "occurrence": {"uk": "випадок, подія", "example": "A solar eclipse is a rare occurrence."},
    "worcester": {"delete": True},
    "respected": {"uk": "шанований, поважний", "example": "She is a highly respected scientist."},
    "independently": {"uk": "незалежно", "example": "She has been living independently since she was 18."},
    "restrict": {"uk": "обмежувати", "example": "The new law will restrict the sale of alcohol."},
    "liabilities": {"uk": "зобов'язання, пасиви", "example": "The company has huge liabilities."},
    "portraits": {"uk": "портрети", "example": "The gallery has a fine collection of portraits."},
    "interpreted": {"uk": "інтерпретований, розтлумачений", "example": "His comments were interpreted as a threat."},
    "confusion": {"uk": "плутанина, збентеження", "example": "There was some confusion about the arrangements for the meeting."},
    "namespace": {"uk": "простір імен", "example": "The XML namespace provides a way to avoid element name conflicts."},
    "programmers": {"uk": "програмісти", "example": "A team of programmers is working on the new software."},
    "upgrading": {"uk": "оновлення, модернізація", "example": "The company is upgrading its computer systems."},
    "frontpage": {"uk": "передня сторінка", "example": "The story was on the frontpage of every newspaper."},
    "demanding": {"uk": "вимогливий", "example": "She has a very demanding job."},
    "flashers": {"delete": True},
    "forbidden": {"uk": "заборонений", "example": "Smoking is forbidden in this building."},
    "possibilities": {"uk": "можливості", "example": "There are endless possibilities for a career in this field."},
    "peripheral": {"uk": "периферійний", "example": "The book contains a great deal of peripheral detail."},
    "furnishings": {"uk": "меблі, умеблювання", "example": "The apartment has modern furnishings."},
    "expressions": {"uk": "вирази", "example": "He has some very strange expressions."},
    "downloading": {"uk": "завантаження", "example": "I'm downloading a new game."},
    "negotiation": {"uk": "переговори", "example": "The negotiation process was long and difficult."},
    "bibliography": {"uk": "бібліографія", "example": "The book includes a useful bibliography."},
    # Words from 8000-9399
    "groove": {"uk": "паз, канавка", "example": "The needle is stuck in the groove of the record."},
    "vagina": {"delete": True},
    "zoloft": {"delete": True},
    "gossip": {"uk": "плітки", "example": "I don't like to listen to gossip."},
    "sleeps": {"uk": "спить", "example": "The baby sleeps for ten hours every night."},
    "petite": {"uk": "мініатюрний", "example": "She is a petite woman, with delicate features."},
    "vertex": {"uk": "вершина", "example": "The vertex of the triangle is the point opposite the base."},
    "wiring": {"uk": "проводка", "example": "The wiring in this house is very old."},
    "wesley": {"delete": True},
    "picnic": {"uk": "пікнік", "example": "Let's have a picnic in the park."},
    "baking": {"uk": "випічка", "example": "I love the smell of baking bread."},
    "bufing": {"delete": True},
    "velvet": {"uk": "оксамит", "example": "She was wearing a beautiful velvet dress."},
    "greene": {"delete": True},
    "savage": {"uk": "дикий, жорстокий", "example": "The team faced a savage attack from their opponents."},
    "apollo": {"delete": True},
    "willow": {"uk": "верба", "example": "There is a large willow tree by the river."},
    "guyana": {"delete": True},
    "affair": {"uk": "справа, роман", "example": "He had an affair with his secretary."},
    "hollow": {"uk": "порожнистий", "example": "The tree was hollow inside."},
    "bloody": {"uk": "кривавий", "example": "He had a bloody nose after the fight."},
    "justify": {"uk": "виправдовувати", "example": "How can you justify your actions?"},
    "abraham": {"delete": True},
    "bedford": {"delete": True},
    "prayers": {"uk": "молитви", "example": "Her prayers were finally answered."},
    "blowing": {"uk": "дме", "example": "The wind is blowing hard today."},
    "nirvana": {"delete": True},
    "wishing": {"uk": "бажаючи", "example": "I was just wishing you were here."},
    "expired": {"uk": "прострочений", "example": "My passport has expired."},
    "pulling": {"uk": "тягнучи", "example": "She was pulling a heavy suitcase."},
    "emperor": {"uk": "імператор", "example": "The Roman emperor lived in a grand palace."},
    "workout": {"uk": "тренування", "example": "I do a 30-minute workout every morning."},
    "penguin": {"uk": "пінгвін", "example": "Penguins are birds that cannot fly."},
    "wrapped": {"uk": "загорнутий", "example": "The gift was beautifully wrapped in gold paper."},
    "labeled": {"uk": "позначений", "example": "Each item was clearly labeled with the price."},
    "ecology": {"uk": "екологія", "example": "She is studying the ecology of the Amazon rainforest."},
    "toolkit": {"uk": "набір інструментів", "example": "He has a well-equipped toolkit for home repairs."},
    "bouquet": {"uk": "букет", "example": "He sent her a beautiful bouquet of flowers."},
    "assists": {"uk": "допомагає", "example": "He assists the manager with his work."},
    "pressed": {"uk": "натиснутий", "example": "She pressed the button to call the elevator."},
    "refresh": {"uk": "освіжити", "example": "I need to refresh my memory of the details."},
    "expects": {"uk": "очікує", "example": "The company expects to make a profit this year."},
    "jumping": {"uk": "стрибки", "example": "The children were jumping up and down with excitement."},
    "hygiene": {"uk": "гігієна", "example": "Good personal hygiene is very important."},
    "halifax": {"delete": True},
    "viewers": {"uk": "глядачі", "example": "The show has millions of viewers."},
    "vanilla": {"uk": "ваніль", "example": "I'll have a vanilla ice cream, please."},
    "backing": {"uk": "підтримка", "example": "The project has the backing of the government."},
    "reservoir": {"uk": "водосховище", "example": "The city's water comes from a large reservoir in the hills."},
    "survivor": {"uk": "вцілілий", "example": "He was the sole survivor of the plane crash."},
    "firmware": {"uk": "прошивка", "example": "You need to update the firmware on your router."},
    "shepherd": {"uk": "пастух", "example": "The shepherd guided his flock of sheep."},
    "canberra": {"delete": True},
    "librarian": {"uk": "бібліотекар", "example": "The librarian helped me find the book I was looking for."},
    "potatoes": {"uk": "картопля", "example": "I love roasted potatoes with rosemary."},
    "lightbox": {"uk": "лайтбокс", "example": "The photographer used a lightbox to view the negatives."},
    "thereafter": {"uk": "після цього", "example": "He left the company soon thereafter."},
    "hardwood": {"uk": "листяна деревина", "example": "The floor was made of polished hardwood."},
    "thorough": {"uk": "ретельний", "example": "The police carried out a thorough investigation."},
    "asbestos": {"uk": "азбест", "example": "Asbestos is a dangerous substance that can cause cancer."},
    "mediawiki": {"delete": True},
    "evanescence": {"delete": True},
    "fuzzy": {"uk": "нечіткий, пухнастий", "example": "The photo was a bit fuzzy."},
    "pensions": {"uk": "пенсії", "example": "He receives a small pension from the state."},
    "crossword": {"uk": "кросворд", "example": "I do the crossword in the newspaper every day."},
    "optimize": {"uk": "оптимізувати", "example": "We need to optimize our apges for mobile devices."},
    "endangered": {"uk": "під загрозою зникнення", "example": "The giant panda is an endangered species."},
    "survivors": {"uk": "вцілілі", "example": "There were no survivors of the crash."},
    "positioning": {"uk": "позиціонування", "example": "The company is trying to improve its market positioning."},
    "attacked": {"uk": "атакований", "example": "The village was attacked by enemy forces."},
    "bleeding": {"uk": "кровотеча", "example": "She was bleeding heavily from a cut on her head."},
    "johnston": {"delete": True},
    "greensboro": {"delete": True},
    "recovered": {"uk": "одужав", "example": "He has fully recovered from the illness."},
    "simpsons": {"delete": True},
    "defensive": {"uk": "оборонний", "example": "The team played a very defensive game."},
    "arrivals": {"uk": "прибуття", "example": "The arrivals hall was crowded with people."},
    "frankfurt": {"delete": True},
    "activists": {"uk": "активісти", "example": "A group of environmental activists were protesting outside the factory."},
    "opponents": {"uk": "супротивники", "example": "He is a formidable opponent in a debate."},
    "examining": {"uk": "оглядаючи", "example": "The doctor is examining the patient."},
    "promptly": {"uk": "негайно", "example": "She replied to my email very promptly."},
    "sexually": {"uk": "сексуально", "example": "The film contains some sexually explicit scenes."},
    "springer": {"delete": True},
    "avoiding": {"uk": "уникаючи", "example": "He is avoiding me for some reason."},
    "sympathy": {"uk": "співчуття", "example": "I have a lot of sympathy for her."},
    "detective": {"uk": "детектив", "example": "He is a private detective."},
    "experiencing": {"uk": "переживаючи", "example": "She is experiencing a lot of pain."},
    "textiles": {"uk": "текстиль", "example": "The city is famous for its textiles."},
    "surprising": {"uk": "дивовижний", "example": "It's surprising how many people don't know how to cook."},
    "powerseller": {"delete": True},
    "aquarium": {"uk": "акваріум", "example": "We have a large aquarium with tropical fish."},
    "paintball": {"uk": "пейнтбол", "example": "We went paintballing for my birthday."},
    "intention": {"uk": "намір", "example": "I have no intention of changing my mind."},
    "albuquerque": {"delete": True},
    "sociology": {"uk": "соціологія", "example": "She is studying sociology at university."},
    "invasion": {"uk": "вторгнення", "example": "The country is preparing for an invasion."},
    "lightweight": {"uk": "легкий", "example": "This is a very lightweight jacket."},
    "invitation": {"uk": "запрошення", "example": "I received an invitation to their wedding."},
    "psychology": {"uk": "психологія", "example": "He is a professor of psychology."},
    "biography": {"uk": "біографія", "example": "She wrote a biography of Winston Churchill."},
    "geography": {"uk": "географія", "example": "I'm not very good at geography."},
    "genealogy": {"uk": "генеалогія", "example": "He is an expert in Irish genealogy."},
    "physiology": {"uk": "фізіологія", "example": "She is studying human physiology."},
    "zoophilia": {"delete": True},
    "shakespeare": {"delete": True},
    "pathology": {"uk": "патологія", "example": "He is a professor of pathology."},
    "invention": {"uk": "винахід", "example": "The invention of the internet changed the world."},
    "sentences": {"uk": "речення", "example": "The judge gave him a long prison sentence."},
    "gradually": {"uk": "поступово", "example": "The weather is gradually getting warmer."},
    "traveller": {"uk": "мандрівник", "example": "He is an experienced traveller."},
    "beginners": {"uk": "початківці", "example": "This is a course for beginners."},
    "adaptive": {"uk": "адаптивний", "example": "The company has an adaptive approach to business."},
    "receivers": {"uk": "приймачі", "example": "The radio receivers are not working properly."},
    "writings": {"uk": "твори", "example": "She is a well-known writer, and her writings are very popular."},
    "omissions": {"uk": "упущення", "example": "There are several omissions in the report."},
    "manually": {"uk": "вручну", "example": "The machine has to be operated manually."},
    "conviction": {"uk": "засудження, переконання", "example": "He has a previous conviction for theft."},
    "privileges": {"uk": "привілеї", "example": "He enjoys all the privileges of wealth."},
    "crawford": {"delete": True},
    "explaining": {"uk": "пояснюючи", "example": "He is explaining the rules of the game."},
    "apparatus": {"uk": "апарат, прилад", "example": "The laboratory has all the latest scientific apparatus."},
    "suburban": {"uk": "приміський", "example": "They live in a quiet suburban street."},
    "basename": {"delete": True},
    "rendering": {"uk": "візуалізація", "example": "The architect showed us a rendering of the new building."},
    "reporters": {"uk": "репортери", "example": "A crowd of reporters were waiting outside the court."},
    "aberdeen": {"delete": True},
    "waterproof": {"uk": "водонепроникний", "example": "I need a waterproof jacket for the trip."},
    "entrepreneur": {"uk": "підприємець", "example": "He is a successful entrepreneur who started his own business."},
    "gibraltar": {"delete": True},
    "publicity": {"uk": "публічність, розголос", "example": "The company is trying to get more publicity for its new product."},
    "convergence": {"uk": "конвергенція, зближення", "example": "The convergence of two rivers."},
    "theology": {"uk": "теологія, богослов'я", "example": "He is a student of theology."},
    "viking": {"delete": True},
    "banana": {"uk": "банан", "example": "I had a banana for breakfast."},
    "freeze": {"uk": "заморожувати", "example": "The river freezes over in winter."},
    "griffin": {"delete": True},
    "seekers": {"uk": "шукачі", "example": "They are seekers of truth and knowledge."},
    "baghdad": {"delete": True},
    "biology": {"uk": "біологія", "example": "She is a professor of biology."},
    "geology": {"uk": "геологія", "example": "He is studying geology at university."},
    "possess": {"uk": "володіти", "example": "He possesses great apgitude and intelligence."},
    "lafayette": {"delete": True},
    "maximize": {"uk": "максимізувати", "example": "We need to maximize our profits."},
    "paragraphs": {"uk": "абзаци", "example": "The first two paragraphs of the article are the most important."},
    "inexpensive": {"uk": "недорогий", "example": "This is an inexpensive but effective solution."},
    "engaging": {"uk": "захоплюючий", "example": "He is an engaging speaker."},
    "annoying": {"uk": "дратівливий", "example": "That noise is very annoying."},
    "highways": {"uk": "шосе", "example": "The new highway will reduce travel time."},
    "performer": {"uk": "виконавець", "example": "She is a talented performer."},
    "opponent": {"uk": "суперник", "example": "He is a difficult opponent to beat."},
    "prototype": {"uk": "прототип", "example": "They have built a prototype of the new car."},
    "dependence": {"uk": "залежність", "example": "The country's dependence on oil is a problem."},
    "beginner": {"uk": "початківець", "example": "This is a good book for a beginner."},
    "likewise": {"uk": "так само", "example": "She is a good student, and her brother is likewise."},
    "dividend": {"uk": "дивіденд", "example": "The company paid a large dividend to its shareholders."},
    "invision": {"delete": True},
    "webpage": {"uk": "веб-сторінка", "example": "I found the information on their webpage."},
    "playback": {"uk": "відтворення", "example": "The video playback is very smooth."},
    "knitting": {"uk": "в'язання", "example": "She enjoys knitting in her spare time."},
    "workflow": {"uk": "робочий процес", "example": "We need to improve our workflow to be more efficient."},
    "deferred": {"uk": "відкладений", "example": "The meeting has been deferred until next week."}
}

# Words to delete
words_to_delete = [
    "lafayette", "baghdad", "gibraltar", "griffin", "aberdeen", "crawford", "fairfield"
]

# List to store deleted words
deleted_words_log = []

# Iterate over the DataFrame and apply corrections
for index, row in df.iterrows():
    word = row['word']
    
    if word in corrections:
        correction_data = corrections[word]
        if correction_data.get("delete"):
            deleted_words_log.append(word)
            df.drop(index, inplace=True)
        else:
            if "uk" in correction_data:
                df.at[index, 'uk'] = correction_data["uk"]
            if "example" in correction_data:
                df.at[index, 'example'] = correction_data["example"]
    elif word in words_to_delete:
        deleted_words_log.append(word)
        df.drop(index, inplace=True)

# Restore original column labels before saving the updated dataset
column_mapping_to_external = {v: k for k, v in column_mapping_to_internal.items()}
df.rename(
    columns={src: dst for src, dst in column_mapping_to_external.items() if src in df.columns},
    inplace=True,
)

# Save the updated DataFrame to a new CSV file
df.to_csv('assets/data/sets/combined_words_updated.csv', index=False)

# Print the list of deleted words
print("Deleted words:", deleted_words_log)
