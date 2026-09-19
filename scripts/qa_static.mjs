import fs from 'node:fs';

const errors = [];
const html = fs.readFileSync('index.html', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');

try {
  new Function(app);
} catch (error) {
  errors.push('app.js syntax: ' + error.message);
}

const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(m => m[1]);
const duplicateIds = ids.filter((id, i) => ids.indexOf(id) !== i);
if (duplicateIds.length) errors.push('duplicate IDs: ' + [...new Set(duplicateIds)].join(', '));

const localRefs = [...html.matchAll(/(?:href|src)="\.\/([^"?#]+)/g)].map(m => m[1]);
for (const ref of localRefs) {
  if (!fs.existsSync(ref)) errors.push('missing local asset: ' + ref);
}

for (const required of [
  'tradeActionBox','tradeActionLabel','tradeActionDetail','watchOptionsToggle',
  'trendWatchOptions','results','refreshButton','mt5Execution'
]) {
  if (!html.includes(`id="${required}"`)) errors.push('missing required id: ' + required);
}

if (errors.length) {
  console.error(errors.join('\n'));
  process.exit(1);
}
console.log('Static QA passed');
