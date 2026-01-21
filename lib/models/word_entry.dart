class WordEntry {
  final String level;
  final String sublist;
  final String wordMain; // The word being learned
  final String wordSyn;  // Synonym or alternative for the word
  final String trans1;   // Primary translation
  final String trans2;   // Secondary translation
  
  // Keep legacy examples for internal data mapping if needed, but we focus on synonyms
  final String example1;
  final String example2;
  final String example3;
  final String example4;

  WordEntry(this.level, this.sublist, this.wordMain, this.trans1, 
      [this.example1 = '', this.example2 = '', this.example3 = '', 
       this.example4 = '', this.wordSyn = '', this.trans2 = '']);
}
