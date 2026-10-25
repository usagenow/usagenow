// Apply reviewed Kazakh, Uzbek (user-specified Ö Ğ Ş Ç), and Turkish copy.
import fs from 'node:fs';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '..');
const translations = JSON.parse(fs.readFileSync(path.join(root, 'scripts/translations-1.0.json'), 'utf8'));
const catalogPath = path.join(root, 'Shared/Resources/Localizable.xcstrings');
const catalog = JSON.parse(fs.readFileSync(catalogPath, 'utf8'));
const providers = ['JetBrains AI', 'Codex', 'Claude Code', 'Gemini CLI', 'Antigravity', 'Kiro', 'Warp', 'OpenCode', 'Qoder', 'Qwen Code', 'Cline', 'Grok Build', 'Windsurf', 'DeepSeek', 'Kimi', 'OpenRouter', 'Ollama', 'Cursor', 'GitHub Copilot', 'Perplexity', 'ElevenLabs', 'Z.ai'];
for (const provider of providers) {
  translations[`${provider} usage`] = translations['%@ usage'].map(value => value.replace('%@', provider));
}
const tracking = {
  'Track AI Assistant limits from your JetBrains IDE.': ['JetBrains IDE ішіндегі AI Assistant лимиттерін бақылау.', 'JetBrains IDE’dagi AI Assistant limitlarini kuzatiş.', 'JetBrains IDE’nizdeki AI Assistant limitlerini izleyin.'],
  'Open a JetBrains IDE with AI Assistant enabled to update usage limits.': ['Лимиттерді жаңарту үшін AI Assistant қосылған JetBrains IDE ашыңыз.', 'Limitlarni yangilaş uçun AI Assistant yoqilgan JetBrains IDE’ni oçing.', 'Limitleri güncellemek için AI Assistant etkin bir JetBrains IDE açın.'],
  'Track Antigravity limits while the Antigravity app runs.': ['Antigravity жұмыс істегенде лимиттерін бақылау.', 'Antigravity işlayotganda limitlarini kuzatiş.', 'Antigravity çalışırken limitlerini izleyin.'],
  'Track Claude Code usage and limits.': ['Claude Code қолданысы мен лимиттерін бақылау.', 'Claude Code sarfi va limitlarini kuzatiş.', 'Claude Code kullanımını ve limitlerini izleyin.'],
  'Track Codex usage and limits.': ['Codex қолданысы мен лимиттерін бақылау.', 'Codex sarfi va limitlarini kuzatiş.', 'Codex kullanımını ve limitlerini izleyin.'],
  'Track Cline tokens, requests, and cost.': ['Cline токендерін, сұраулары мен құнын бақылау.', 'Cline tokenlari, sörovlari va xarajatini kuzatiş.', 'Cline tokenlarını, isteklerini ve maliyetini izleyin.'],
  'Track Copilot allowances and credits.': ['Copilot квоталары мен кредиттерін бақылау.', 'Copilot kvotalari va kreditlarini kuzatiş.', 'Copilot kullanım haklarını ve kredilerini izleyin.'],
  'Track Cursor plan usage.': ['Cursor тарифінің қолданысын бақылау.', 'Cursor tarifi sarfini kuzatiş.', 'Cursor plan kullanımını izleyin.'],
  'Track ElevenLabs character usage.': ['ElevenLabs таңба қолданысын бақылау.', 'ElevenLabs belgi sarfini kuzatiş.', 'ElevenLabs karakter kullanımını izleyin.'],
  'Track Gemini CLI activity by model.': ['Gemini CLI белсенділігін модель бойынша бақылау.', 'Gemini CLI faolligini model böyiça kuzatiş.', 'Gemini CLI etkinliğini modele göre izleyin.'],
  'Track Grok Build tokens, models, and cost.': ['Grok Build токендерін, модельдері мен құнын бақылау.', 'Grok Build tokenlari, modellari va xarajatini kuzatiş.', 'Grok Build tokenlarını, modellerini ve maliyetini izleyin.'],
  'Track Kiro credits and monthly limits.': ['Kiro кредиттері мен айлық лимиттерін бақылау.', 'Kiro kreditlari va oylik limitlarini kuzatiş.', 'Kiro kredilerini ve aylık limitlerini izleyin.'],
  'Track Ollama Cloud session and weekly limits.': ['Ollama Cloud сеанс және апталық лимиттерін бақылау.', 'Ollama Cloud seans va haftalik limitlarini kuzatiş.', 'Ollama Cloud oturum ve haftalık limitlerini izleyin.'],
  'Track OpenCode tokens and models.': ['OpenCode токендері мен модельдерін бақылау.', 'OpenCode tokenlari va modellarini kuzatiş.', 'OpenCode tokenlarını ve modellerini izleyin.'],
  'Track OpenRouter spending and key limits.': ['OpenRouter шығындары мен кілт лимиттерін бақылау.', 'OpenRouter xarajati va kalit limitlarini kuzatiş.', 'OpenRouter harcamalarını ve anahtar limitlerini izleyin.'],
  'Track Perplexity web credits.': ['Perplexity вебкредиттерін бақылау.', 'Perplexity veb kreditlarini kuzatiş.', 'Perplexity web kredilerini izleyin.'],
  'Track Qoder credits.': ['Qoder кредиттерін бақылау.', 'Qoder kreditlarini kuzatiş.', 'Qoder kredilerini izleyin.'],
  'Track Qwen Code tokens and models.': ['Qwen Code токендері мен модельдерін бақылау.', 'Qwen Code tokenlari va modellarini kuzatiş.', 'Qwen Code tokenlarını ve modellerini izleyin.'],
  'Track Warp agent requests and credits.': ['Warp агентінің сұраулары мен кредиттерін бақылау.', 'Warp agent sörovlari va kreditlarini kuzatiş.', 'Warp ajan isteklerini ve kredilerini izleyin.'],
  'Track Windsurf daily and weekly limits.': ['Windsurf күндік және апталық лимиттерін бақылау.', 'Windsurf kunlik va haftalik limitlarini kuzatiş.', 'Windsurf günlük ve haftalık limitlerini izleyin.'],
  'Track Z.ai Coding Plan limits.': ['Z.ai Coding Plan лимиттерін бақылау.', 'Z.ai Coding Plan limitlarini kuzatiş.', 'Z.ai Coding Plan limitlerini izleyin.'],
  'Track your DeepSeek API balance.': ['DeepSeek API балансын бақылау.', 'DeepSeek API balansini kuzatiş.', 'DeepSeek API bakiyenizi izleyin.'],
  'Track your Kimi API balance.': ['Kimi API балансын бақылау.', 'Kimi API balansini kuzatiş.', 'Kimi API bakiyenizi izleyin.'],
};
Object.assign(translations, tracking);
const setup = JSON.parse(fs.readFileSync(path.join(root, 'scripts/translations-setup.json'), 'utf8'));
for (const [key, values] of Object.entries(setup)) {
  const entry = catalog.strings[key] ??= {};
  entry.localizations ??= {};
  for (const [i, language] of ['ru', 'de', 'es', 'fr', 'nl', 'pt', 'he', 'ja', 'ko'].entries()) {
    entry.localizations[language] = {stringUnit: {state: 'translated', value: values[i]}};
  }
}
for (const provider of ['Claude', 'Antigravity']) translations[`${provider} usage limits are temporarily unavailable.`] = translations['%@ usage limits are temporarily unavailable.'].map(value => value.replace('%@', provider));
// Explicit new keys are added before the next Xcode extraction pass.
for (const key of Object.keys(translations)) catalog.strings[key] ??= {};
const missing = [];
for (const [key, entry] of Object.entries(catalog.strings)) {
  if (key === '%@') entry.shouldTranslate = false;
  if (entry.extractionState === 'stale' || entry.shouldTranslate === false) continue;
  const values = translations[key];
  if (!values) { missing.push(key); continue; }
  entry.localizations ??= {};
  for (const [i, language] of ['kk', 'uz', 'tr'].entries()) {
    entry.localizations[language] = {stringUnit: {state: 'translated', value: values[i]}};
  }
}
fs.writeFileSync(catalogPath, JSON.stringify(catalog, null, 2).replace(/^(\s*"(?:[^"\\]|\\.)*"):/gm, '$1 :') + '\n');
console.log(`1.0 translations: ${Object.keys(translations).length} entries; ${missing.length} missing`);
if (missing.length) { console.error(missing.join('\n')); process.exitCode = 1; }
