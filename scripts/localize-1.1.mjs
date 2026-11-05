import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
const root = path.resolve(import.meta.dirname, '..');
const { keys, translations } = JSON.parse(fs.readFileSync(path.join(root, 'scripts/translations-1.1.json'), 'utf8'));
assert.equal(new Set(keys).size, keys.length);
assert.equal(Object.keys(translations).length, 12);
const file = path.join(root, 'Shared/Resources/Localizable.xcstrings');
let original = fs.readFileSync(file, 'utf8');
const catalog = JSON.parse(original);
const argumentsIn = value => [...value.matchAll(/%(?:\d+\$)?[@dfius]/g)].map(match => match[0].replace(/\d+\$/, '')).sort();
for (const [locale, values] of Object.entries(translations)) {
  assert.equal(values.length, keys.length, locale);
  for (const [index, key] of keys.entries()) {
    assert.deepEqual(argumentsIn(values[index]), argumentsIn(key), `${locale}: ${key}`);
    const entry = catalog.strings[key] ??= { extractionState: 'manual' };
    entry.localizations ??= {};
    entry.localizations[locale] = { stringUnit: { state: 'translated', value: values[index] } };
  }
}
// Keep older translations and Xcode's formatting byte-for-byte. Only these
// release-specific entries are written; compiler sync must not mark unrelated
// keys stale or produce a whole-catalog formatting diff.
for (const key of keys) {
  const entry = JSON.stringify({ [key]: catalog.strings[key] }, null, 2)
    .replace(/^(\s*"(?:[^"\\]|\\.)*"):/gm, '$1 :').slice(2, -2)
    .split('\n').map(line => '  ' + line).join('\n');
  const escaped = JSON.stringify(key).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const pattern = new RegExp('^    ' + escaped + '\\s*:\\s*\\{[\\s\\S]*?^    \\}', 'm');
  if (pattern.test(original)) original = original.replace(pattern, () => entry);
  else {
    const marker = '\n  },\n  "version"';
    const end = original.lastIndexOf(marker);
    assert(end > 0);
    original = original.slice(0, end) + ',\n' + entry + original.slice(end);
  }
}
JSON.parse(original);
fs.writeFileSync(file, original);
console.log(`Localized ${keys.length} interface strings in 13 languages; format arguments verified.`);

// Bundled notes use the same terminology as the translated interface.
for (const locale of ['en', ...Object.keys(translations)]) {
  const text = key => locale === 'en' ? key : translations[locale][keys.indexOf(key)];
  const items = [
    `${text('Overview')} — ${[text('Today'), text('7 days'), text('30 days')].join(' / ')}. ${text('Local activity recorded on this Mac. History may be incomplete.')}`,
    `${text('Account sets')} — ${text('Sets change what you see. Enabled accounts keep updating and sending notifications.')}`,
    `${text('Separate provider icons')} — ${text('Show selected provider icons and usage side by side in the menu bar.')}`,
    `${text('Adaptive')} — ${text('Adaptive refresh follows each account, network availability, power mode and screen lock. Server cooldowns always apply.')}`,
    `${text('Balance and budgets')} — ${text('Budget alerts at 80% and 100% of reported spend.')} ${text('Alerts only. Budgets do not block spending. Reported spend uses the provider’s time zone; API price estimates are excluded.')}`,
    `MiniMax — ${text('Track MiniMax M Plan limits.')}`,
  ];
  const notes = `## 1.1.0\n\n### Added\n\n${items.map(item => '- ' + item).join('\n')}\n\n`;
  const notesFile = path.join(root, locale === 'en' ? 'CHANGELOG.md' : `UsageNow/Resources/Changelog/CHANGELOG.${locale}.md`);
  const old = fs.readFileSync(notesFile, 'utf8');
  const first = old.search(/^## \d/m);
  const rest = old.slice(first).replace(/^## 1\.1\.0\n[\s\S]*?(?=^## \d|$(?![\s\S]))/m, '');
  fs.writeFileSync(notesFile, old.slice(0, first) + notes + rest);
}
