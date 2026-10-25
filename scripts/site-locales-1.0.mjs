// Generate explicit locale properties using reviewed strings, retaining the
// site's established per-component dictionaries and template expressions.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const root = path.resolve(import.meta.dirname, '../../UsageNow');
const require = createRequire(path.join(root, 'package.json'));
const ts = require('typescript');
const dictionaryFile = path.join(import.meta.dirname, 'site-translations-1.0.json');
const dictionary = {
  ...JSON.parse(fs.readFileSync(path.join(import.meta.dirname, 'translations-1.0.json'), 'utf8')),
  ...(fs.existsSync(dictionaryFile) ? JSON.parse(fs.readFileSync(dictionaryFile, 'utf8')) : {}),
};
const strings = new Set();
const missing = new Set();
const localeCodes = ['kk', 'uz', 'tr'];
const apply = process.argv.includes('--apply');

function textKey(node) {
  if (ts.isTemplateExpression(node)) return node.head.text + node.templateSpans.map((span, i) => '${' + i + '}' + span.literal.text).join('');
  return node.text;
}
function technical(value) {
  return /^(https?:|\/|#|window:|\d|[a-z]+_[A-Z]+$)/.test(value) ||
    ['', 'notAvailable', 'notReported', 'unavailable', 'antigravity', 'kiroLog', 'database', 'priceTable', 'officialApi', 'xAI', 'en', 'EN', 'experimental', 'local', 'keychain', 'official', 'neutral', 'folder', 'cloud', 'github', 'x', 'README.md', 'CHANGELOG.md', 'MIT', 'UsageNow', 'Codex', 'Claude Code', 'Gemini CLI', 'Antigravity', 'Kiro', 'Warp', 'OpenCode', 'Qoder', 'Qwen Code', 'Cline', 'Grok Build', 'Windsurf', 'JetBrains AI', 'DeepSeek', 'Kimi', 'OpenRouter', 'Ollama Cloud', 'Cursor', 'GitHub Copilot', 'Perplexity', 'ElevenLabs', 'Z.ai', 'API', 'CLI', 'GitHub', 'macOS', 'Mac', 'X'].includes(value);
}
function values(node, visit) {
  if (ts.isPropertyAssignment(node)) return values(node.initializer, visit);
  if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node) || ts.isTemplateExpression(node)) return visit(node);
  ts.forEachChild(node, child => values(child, visit));
}
for (const directory of ['lib', 'components']) {
  for (const relative of fs.readdirSync(path.join(root, directory), {recursive: true})) {
    if (!/\.tsx?$/.test(relative)) continue;
    const file = path.join(root, directory, relative);
    if (file === path.join(root, 'lib/i18n.ts')) continue;
    const source = fs.readFileSync(file, 'utf8');
    const tree = ts.createSourceFile(file, source, ts.ScriptTarget.Latest, true);
    const edits = [];
    function walk(node) {
      if (ts.isObjectLiteralExpression(node)) {
        const english = node.properties.find(property => ts.isPropertyAssignment(property) && property.name?.text === 'en');
        if (english) {
          const original = english.initializer;
          values(original, value => { const key = textKey(value); if (!technical(key)) strings.add(key); });
          const needed = localeCodes.filter(locale => !node.properties.some(property => property.name?.text === locale));
          if (needed.length) {
            const copies = needed.map((locale, i) => {
              const index = localeCodes.indexOf(locale);
              let expression = original.getText(tree);
              const replacements = [];
              values(original, value => {
                const key = textKey(value);
                if (technical(key)) return;
                const translated = dictionary[key]?.[index];
                if (translated === undefined) { missing.add(key); return; }
                let output;
                if (ts.isTemplateExpression(value)) {
                  output = '`' + translated.replace(/[`\\]/g, '\\$&').replace(/\$\{(\d+)\}/g, (_, n) => '${' + value.templateSpans[Number(n)].expression.getText(tree).replace(/(["'])en\1/g, JSON.stringify(locale)) + '}') + '`';
                } else output = JSON.stringify(translated);
                replacements.push({start: value.getStart(tree) - original.getStart(tree), end: value.end - original.getStart(tree), output});
              });
              for (const edit of replacements.sort((a, b) => b.start - a.start)) expression = expression.slice(0, edit.start) + edit.output + expression.slice(edit.end);
              expression = expression.replace(/(["'])en\1/g, JSON.stringify(locale));
              return `\n  ${locale}: ${expression},`;
            }).join('');
            // Insert before en; no comma or comment positioning assumptions.
            edits.push({start: english.getStart(tree), output: copies + '\n  '});
          }
        }
      }
      ts.forEachChild(node, walk);
    }
    walk(tree);
    if (apply && !missing.size) {
      let output = source;
      for (const edit of edits.sort((a, b) => b.start - a.start)) output = output.slice(0, edit.start) + edit.output + output.slice(edit.start);
      if (output !== source) fs.writeFileSync(file, output);
    }
  }
}
console.log(`${strings.size} public strings; ${missing.size} missing reviewed translations`);
if (!apply) console.log([...strings].filter(value => !dictionary[value]).map(value => JSON.stringify(value)).join('\n'));
if (apply && missing.size) { console.error([...missing].map(value => JSON.stringify(value)).join('\n')); process.exitCode = 1; }
