// Construit Live/dist : jeu.html (polices et mots intégrés) + serveur.js en un seul fichier.
// Usage : node Live/build.mjs   (les cartes viennent de Shared/cards.tsv, sans Football ni Cinéma)
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url)), root = path.join(here, '..'), out = path.join(here, 'dist');
mkdirSync(out, { recursive: true });
const font = f => readFileSync(path.join(root, 'App/Resources/Fonts', f)).toString('base64');
const words = readFileSync(path.join(root, 'Shared/cards.tsv'), 'utf8').split('\n')
  .filter(l => l && !l.startsWith('#')).map(l => l.split('\t'))
  .filter(c => c.length >= 4 && ['F', 'M'].includes(c[0]) && !['Football', 'Cinéma'].includes(c[1]) && !/foot|ballon d|but\b/i.test(c[2] + ' ' + c[3]))
  .map(c => [c[0], c[1], c[2].trim(), c[3].trim()]);
const html = readFileSync(path.join(here, 'jeu.src.html'), 'utf8')
  .replace('{{FRAUNCES}}', font('Fraunces-Black.ttf')).replace('{{SERIF}}', font('InstrumentSerif-Regular.ttf')).replace('{{SERIF_IT}}', font('InstrumentSerif-Italic.ttf'))
  .replace('{{WORDS}}', JSON.stringify(words));
writeFileSync(path.join(out, 'jeu.html'), html);
console.log(`jeu.html : ${words.length} mots, ${Math.round(html.length / 1024)} Ko`);
