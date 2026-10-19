// Prepare the exact Gutenberg text editions listed in reader_books_sources.md.
// Usage: node tools/scripts/prepare_reader_books.js <directory-with-pg*.txt>
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const sourceDirectory = process.argv[2];
if (!sourceDirectory) throw new Error('A directory containing the source texts is required.');

const editions = [
  { id: 11, count: 12, heading: /^CHAPTER[ \t]+([IVXLCDM]+)\.[ \t]*$/gm, separateTitle: true },
  { id: 55, count: 24, heading: /^Chapter[ \t]+([IVXLCDM]+)[ \t]*$/gm, separateTitle: true },
  { id: 113, count: 27, heading: /^CHAPTER[ \t]+([IVXLCDM]+)\.?[ \t]*$/gm, separateTitle: true },
  { id: 1661, count: 12, heading: /^([IVXLCDM]+)\.[ \t]+([A-Z0-9’' \-]+)[ \t]*$/gm, separateTitle: false },
  { id: 215, count: 7, heading: /^Chapter[ \t]+([IVXLCDM]+)\.[ \t]+([^\n]+)$/gm, separateTitle: false },
];
const romans = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X',
  'XI', 'XII', 'XIII', 'XIV', 'XV', 'XVI', 'XVII', 'XVIII', 'XIX', 'XX',
  'XXI', 'XXII', 'XXIII', 'XXIV', 'XXV', 'XXVI', 'XXVII'];
const outputDirectory = path.resolve(__dirname, '../../assets/data/reader');
fs.mkdirSync(outputDirectory, { recursive: true });

for (const edition of editions) {
  const source = fs.readFileSync(path.join(sourceDirectory, `pg${edition.id}.txt`));
  const raw = source.toString('utf8').replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n');
  const start = raw.search(/^\*\*\* START OF THE PROJECT GUTENBERG EBOOK/m);
  const end = raw.search(/^\*\*\* END OF THE PROJECT GUTENBERG EBOOK/m);
  if (start < 0 || end <= start) throw new Error(`Missing boundary for ${edition.id}`);
  const text = raw.slice(start, end);
  const headings = [...text.matchAll(edition.heading)];
  if (headings.length !== edition.count || headings.some((m, i) => m[1] !== romans[i])) {
    throw new Error(`Unexpected chapters for ${edition.id}: ${headings.map(m => m[1]).join(', ')}`);
  }

  const chapters = headings.map((heading, index) => {
    const limit = index + 1 < headings.length ? headings[index + 1].index : text.length;
    let body = text.slice(heading.index + heading[0].length, limit).trim();
    let title = heading[0].trim();
    if (edition.separateTitle) {
      const titleMatch = body.match(/^([^\n]+)\n+/);
      if (!titleMatch) throw new Error(`Missing title for ${edition.id} chapter ${index + 1}`);
      title = `${title.replace(/\.$/, '')}: ${titleMatch[1].trim()}`;
      body = body.slice(titleMatch[0].length).trim();
    }
    const paragraphs = body.split(/\n[ \t]*\n+/)
      .map(paragraph => {
        const lines = paragraph.split('\n');
        const preserveLineBreaks = lines.some(line => /^ {2,}\S/.test(line));
        return lines.map(line => line.trim()).join(preserveLineBreaks ? '\n' : ' ').trim();
      }).filter(Boolean);
    if (!paragraphs.length) throw new Error(`Empty chapter in ${edition.id}`);
    return { title, paragraphs };
  });
  const filename = path.join(outputDirectory, `${edition.id}.json`);
  fs.writeFileSync(filename, JSON.stringify({ chapters }) + '\n');
  const hash = crypto.createHash('sha256').update(source).digest('hex');
  console.log(`${edition.id}: ${chapters.length} chapters, source SHA-256 ${hash}`);
}
