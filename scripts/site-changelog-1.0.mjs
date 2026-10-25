import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';
const root = path.resolve(import.meta.dirname, '../../UsageNow');
const require = createRequire(path.join(root, 'package.json'));
const ts = require('typescript');
const dictionary = {
  ...JSON.parse(fs.readFileSync(path.join(import.meta.dirname, 'translations-1.0.json'), 'utf8')),
  ...JSON.parse(fs.readFileSync(path.join(import.meta.dirname, 'site-translations-1.0.json'), 'utf8')),
};
const compiled = ts.transpileModule(fs.readFileSync(path.join(root, 'lib/changelog.ts'), 'utf8'), {compilerOptions: {module: ts.ModuleKind.CommonJS}}).outputText;
const exports = {};
vm.runInNewContext(compiled, {exports});
const entries = exports.changelog;
const reviewed = JSON.parse(fs.readFileSync(path.join(import.meta.dirname, 'site-release-translations-1.0.json'), 'utf8'));
for (const entry of entries) {
  const copy = reviewed[entry.version];
  if (!copy) throw new Error('Missing release ' + entry.version);
  const items = entry.sections.flatMap(section => section.items);
  if (copy.items.length !== items.length) throw new Error('Item count changed: ' + entry.version);
  if (copy.summary) dictionary[entry.summary] = copy.summary;
  copy.items.forEach((values, i) => { if (values) dictionary[items[i]] = values; });
}
const missing = new Set();
for (const entry of entries) {
  for (const text of [entry.summary, ...entry.sections.flatMap(section => section.items)]) if (!dictionary[text]) missing.add(text);
}
console.log(`${entries.length} releases; ${missing.size} missing translations`);
if (missing.size) { console.log([...missing].map(value => JSON.stringify(value)).join('\n')); process.exit(); }
if (process.argv.includes('--apply')) {
  const file = path.join(root, 'lib/content/changelog.ts');
  let source = fs.readFileSync(file, 'utf8');
  const tree = ts.createSourceFile(file, source, 99, true);
  const edits = [];
  function walk(node) {
    if (ts.isVariableDeclaration(node) && node.name?.text === 'versions') {
      for (const property of node.initializer.properties) {
        const entry = entries.find(entry => entry.version === property.name?.text);
        if (!entry) continue;
        const locales = ['kk', 'uz', 'tr'].filter(locale => !property.initializer.properties.some(p => p.name?.text === locale));
        const output = locales.map(locale => {
          const index = ['kk', 'uz', 'tr'].indexOf(locale);
          const value = {summary: dictionary[entry.summary][index], sections: Object.fromEntries(entry.sections.map(section => [section.title, section.items.map(text => dictionary[text][index])]))};
          return '\n' + JSON.stringify(locale) + ': ' + JSON.stringify(value, null, 2) + ',\n';
        }).join('');
        if (output) edits.push({start: property.initializer.properties[0].getStart(tree), output});
      }
    }
    ts.forEachChild(node, walk);
  }
  walk(tree);
  for (const edit of edits.sort((a,b) => b.start - a.start)) source = source.slice(0, edit.start) + edit.output + source.slice(edit.start);
  fs.writeFileSync(file, source);
}
if (process.argv.includes('--app-history')) {
  for (const [index, locale] of ['kk', 'uz', 'tr'].entries()) {
    const file = path.resolve(import.meta.dirname, `../UsageNow/Resources/Changelog/CHANGELOG.${locale}.md`);
    const current = fs.readFileSync(file, 'utf8').split('## 0.9.0')[0].trimEnd();
    const history = entries.map(entry => '## ' + entry.version + '\n\n' + entry.sections.map(section => '### ' + section.title + '\n\n' + section.items.map(text => '- ' + dictionary[text][index]).join('\n')).join('\n\n')).join('\n\n');
    fs.writeFileSync(file, current + '\n\n' + history + '\n');
  }
}
