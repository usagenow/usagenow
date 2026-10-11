# Changelog (German)

What's New in German: each version's changes, shorter than CHANGELOG.md. Headings stay in English; the app translates them. A version missing here shows in English.

## 0.8.0

### Added

- Schlüssel, Tokens und Cookies werden vor dem Sichern mit einer schreibgeschützten Nutzungsabfrage geprüft. Klare Meldungen zu Zugangsdaten, Berechtigungen, Netzwerk und Schlüsselbund; Abbrechen lässt die bisherige Verbindung unverändert.
- Bei HTTP 429 pausiert die Verbindung bis zum vom Dienst angegebenen Zeitpunkt. Auch manuelles Aktualisieren respektiert die Pause. Andere Konten laufen weiter, bisherige Werte behalten ihren ursprünglichen Zeitstempel.
- Cursor, GitHub Copilot, Perplexity, ElevenLabs und Z.ai: ausdrückliche Verbindung in den Einstellungen, standardmäßig aus. Cursor und Perplexity bieten ein separates temporäres Anmeldefenster oder manuelle Cookies; Copilot nutzt deinen GitHub-Token. ElevenLabs nutzt die offizielle API, die anderen vier Integrationen sind experimentell. Noch nicht mit echten Konten geprüft.
- Kontoweite Credits und Zeichen stehen getrennt von der heutigen Aktivität. Unbegrenzte oder unbekannte Kontingente werden nicht als erfundene Prozente angezeigt.
- Windsurf: Tages- und Wochenlimits, Rücksetzzeiten und Tarif aus dem lokalen Cache; bei älteren Tarifen Guthaben pro Abrechnungszeitraum. Keine Anmeldedaten und keine Netzwerkanfragen. Noch nicht mit einer aktuellen angemeldeten Installation geprüft.
- Portugiesisch, Japanisch, Koreanisch und Hebräisch: jetzt neun Sprachen. Das Widget unterstützt die Leserichtung von rechts nach links.
- „Neuigkeiten“ ist in allen App-Sprachen verfügbar und funktioniert offline.
- Wähle ein zusätzliches Konto für die Menüleiste, etwa „Codex · Arbeit“. Wird es entfernt, erscheint wieder das erste Konto des Anbieters.

### Fixed

- Das Widget merkt sich den Stand jedes Anbieters. Neue Codex-Daten lassen alte Claude-Limits nicht mehr aktuell aussehen; eine Uhr kennzeichnet ältere Werte.
- Nach dem Zurücksetzen ist der alte Prozentwert unbekannt, bis neue Daten eintreffen. Der Countdown läuft zwischen Widget-Aktualisierungen weiter.
- Ein erneutes Lesen speichert das aktuelle Datum auch bei unverändertem Prozentwert.

### Development

- Debug-Builds verwenden eigene Kennungen und einen eigenen Datencontainer, ohne das installierte Widget zu stören. Automatische Updates sind aus; Tests starten keine echten Anbieter.

## 0.7.2

### Fixed

- Datenschutz und Über ließen sich auf Russisch, Französisch und Spanisch nicht öffnen: Die Tab-Titel passten nicht ins Einstellungsfenster. Es wird jetzt breiter.

## 0.7.1

### Added

- Wähle die Sprache von UsageNow unter Einstellungen › Allgemein › Sprache: wie macOS, oder Deutsch, Englisch, Spanisch, Französisch oder Russisch. Das Widget folgt.
- Benenne einen hinzugefügten Account über sein …-Menü unter Einstellungen › Anbieter um.

### Changed

- Die Aktionen eines hinzugefügten Accounts teilen sich ein Menü, damit die Zeile in jeder Sprache passt.
- Ein leerer oder fehlender Account-Ordner wird als solcher gemeldet, statt zur Anmeldung aufzufordern.

### Fixed

- Ein neuer Account ließ die anderen hinzugefügten Accounts ihre Sitzungen des Monats erneut lesen.

## 0.7.0

### Added

- Mehr als ein Account: ein zweiter Codex- oder Claude Code-Ordner oder ein weiterer API-Schlüssel für DeepSeek, Kimi, OpenRouter oder Ollama Cloud, jeweils mit eigenem Abschnitt – „Codex · Arbeit“ – unter einem Namen deiner Wahl. UsageNow liest nie den Namen oder die E-Mail-Adresse des Accounts.
- Qwen Code – Tokens, Anfragen und Modelle von heute und was sie gekostet hätten, aus den Sitzungsaufzeichnungen, die Qwen Code auf deinem Mac schreibt.
- Cline – Tokens, API-Anfragen und Modelle von heute mit den von Cline erfassten Kosten, aus den Cline-Aufgaben deines Editors und der Cline-CLI. Prompts, Antworten und Schlüssel werden nie gelesen.
- Grok Build – Tokens, Modellaufrufe und Modelle von heute mit den von xAI gemeldeten Kosten, aus den Sitzungsprotokollen von Grok Build.
- Die letzten zwei Wochen im Widget, für Anbieter ohne Limits – die Form deiner Aktivität, nie Beträge.
- UsageNow auf Deutsch, Spanisch, Französisch und Russisch, passend zur Sprache deines Mac.
- Neuigkeiten unter Einstellungen › Über: die Änderungen jeder Version, direkt in der App.

### Changed

- Bei Cline und Grok Build sind die angezeigten Kosten die vom Tool erfassten, keine Schätzung.

## 0.6.1

### Added

- Mitteilungen zu Limits: wenn ein Limit bei 20 % und erneut bei 5 % ist, jeweils einmal, und wenn ein Limit, vor dem du gewarnt wurdest, zurückgesetzt wird. Standardmäßig aus; einschalten unter Einstellungen › Mitteilungen.
- Ein eigener Kurzbefehl, um UsageNow aus jeder App zu öffnen. Nimm ihn unter Einstellungen › Menüleiste auf. Keine zusätzlichen Berechtigungen nötig.

### Changed

- Die Kostenschätzung kennt Claude Sonnet 5.5 und GPT-6.1.

### Fixed

- „Erneut versuchen“, ein neu hinzugefügter API-Schlüssel oder ein gerade eingeschalteter Anbieter konnten ignoriert werden, wenn sie während einer Aktualisierung ausgelöst wurden.
- Antigravity hält andere Anbieter nicht mehr auf, während UsageNow seinen Language-Server sucht.
- Eine sehr lange Zeile in einer Sitzungsdatei wird übersprungen, ohne in den Speicher geladen zu werden.

## 0.6.0

### Added

- Die letzten 30 Tage unter jedem Anbieter: ein Balken pro Tag, mit den Tokens des Monats, geschätzten Kosten und dem meistgenutzten Modell. Zeig auf einen Balken für diesen Tag. Die Diagramme lassen sich unter Einstellungen › Allgemein ausschalten.
- OpenCode – heutige Tokens, Anfragen und Modelle und was sie kosten würden, aus OpenCodes lokaler Datenbank, schreibgeschützt. Prompts und Antworten werden nie gelesen.
- Qoder – heute ausgegebene Credits und die Antworten, für die sie bezahlt wurden, aus den Transkripten, die Qoder auf deinem Mac schreibt. Die Qoder-Anmeldung wird nie geöffnet.
- Ollama Cloud (experimentell) – Sitzungs- und Wochenlimits mit deinem eigenen Cloud-API-Schlüssel.
- Limits als verbleibend oder verbraucht, im Fenster, in der Menüleiste und im Widget.
- Credits im Widget für Kiro, Warp und Qoder.
- Problem melden unter Einstellungen › Über: erst den ganzen Bericht sehen, dann selbst als GitHub-Issue oder E-Mail senden. Keine Namen, Pfade, Schlüssel oder Prompts.

### Changed

- Das Menüleistenfenster ist deckender und scrollt, statt über einen kleinen Bildschirm hinauszuragen.
- Einstellungen › Anbieter passt auf einen Laptop-Bildschirm.
- Die Kostenschätzung kennt die neuesten Modelle, darunter Claude Opus 5.5 und GPT-6.
- Das Lesen eines Monats an Sitzungsdateien ist um ein Vielfaches schneller und braucht weit weniger Speicher.

### Fixed

- Codex-Limits wurden mit ChatGPT 26.9 nicht mehr aktualisiert, weil es seine eingebaute Codex-CLI verschoben hat.
- Veraltete Claude-Limits sagen jetzt, wie man sie aktualisiert, damit ein stundenalter Prozentwert nicht als aktuell gilt.
- Das Widget liest Daten einer neueren App, statt dich zu bitten, UsageNow zu öffnen.
- UsageNow konnte sich kommentarlos beenden, wenn der Codex-App-Server zu früh endete.

## 0.5.0

### Added

- Kiro – das monatliche Credit-Limit deines Tarifs, wann es zurückgesetzt wird, und die heutigen Credits und Prompts, aus dem, was Kiro auf deinem Mac schreibt. Keine Anfrage an Kiro, keine Kiro-Zugangsdaten.
- Warp – heutige Agent-Anfragen, Credits und Tokens je Modell, aus Warps lokaler Datenbank, schreibgeschützt.
- DeepSeek, Kimi und OpenRouter – Guthaben und Ausgaben aus ihren offiziellen APIs, mit deinem eigenen API-Schlüssel. Der Schlüssel bleibt im Schlüsselbund und geht nur an diesen Anbieter. Keiner der drei ist bisher an einem echten Konto geprüft.

### Fixed

- Der Lizenzhinweis von Sparkle steht jetzt unter Über › Open-Source-Lizenzen.

## 0.4.0

### Added

- Was die heutigen Tokens kosten würden: eine Schätzung neben den Summen jedes Anbieters, zu veröffentlichten API-Preisen, zwischengespeicherte Tokens zum Cache-Preis. Eine Größenordnung, keine Rechnung – ein Abo rechnet nicht pro Token ab.
- Updates in der App. UsageNow sucht und installiert eigene Updates, und nur solche mit seiner Signatur. Die Suche sendet nichts über dich. Von 0.3.0 aus installiere 0.4.0 einmal von Hand.

### Changed

- Aktualisieren zeichnet einen Fortschrittsbogen um den Pfeil, statt das Symbol zu drehen.
- Die Prozentzahl in der Menüleiste ist an die Symbole daneben angepasst.

## 0.3.0

### Added

- Antigravity – 5-Stunden- und Wochenlimits je Modellgruppe und dein Tarif, aus der Antigravity-App, solange sie läuft. Keine Zugangsdaten, nichts jenseits von 127.0.0.1.
- Gemini CLI – Tokens, Anfragen und Modelle aus seinen lokalen Sitzungsaufzeichnungen. Es meldet keine Nutzungslimits, daher werden keine angezeigt.
- Aktivität nach Modell: eine Liste „Modelle heute“ für Codex, Claude Code und Gemini CLI, aktivstes zuerst.
- Team-Tarife: Claude zeigt den Platz, etwa Team · Premium; Codex zeigt Team, Business und Enterprise.
- Menüleisten-Modi für Antigravity und Gemini CLI.
- Anbieter per Ziehen in den Einstellungen sortieren; Fenster und Widget folgen.
- Cursor und GitHub Copilot sind als „Demnächst“ aufgeführt.

### Changed

- Ab drei Anbietern zeigt das mittlere Widget eine Zeile pro Anbieter und das kleine bis zu drei – die mit dem knappsten Limit zuerst.
- Ein per Update hinzugefügter Anbieter startet einmal eingeschaltet. Von dir ausgeschaltete bleiben aus.

### Fixed

- Claude-Nutzungslimits fragen nicht mehr nach deinem Anmeldepasswort und kommen nach dem Start von Claude Code von selbst zurück.
- Ein Claude-Limitfenster, das sich in deiner Abwesenheit zurückgesetzt hat, bleibt sichtbar, und erreichte Limits erscheinen ganz ohne Anmeldung.
- Die letzten bekannten Claude-Limits überstehen das Beenden oder Aktualisieren der App.

## 0.2.0

### Added

- Echte Daten: Codex-Limits, Reset-Zeiten und Tarif vom offiziellen Codex-App-Server; Tokens, Anfragen und das letzte Modell für Codex und Claude Code aus lokalen Sitzungsdateien.
- Widgets in kleiner und mittlerer Größe.
- Claude Code-Nutzungslimits – experimentell und standardmäßig aus.
- Codex und Claude Code lassen sich einzeln ein- und ausschalten.
- Menüleisten-Modi: nur Symbol, kritischste Nutzung oder ein Anbieter.
- Helles, dunkles oder System-Erscheinungsbild.

### Changed

- Nutzung erscheint als Rest – „58 % übrig“ – und Balken werden kürzer, je mehr du nutzt.
- Limitfenster erscheinen genau so, wie ein Anbieter sie meldet; ein fehlendes wird nie erfunden.
- Lassen sich Limits nicht lesen, bleiben die letzten bekannten Werte einen Tag, als veraltet markiert, mit einem einzeiligen Grund.

## 0.1.0

### Added

- Die native Menüleisten-App, ihre Einstellungen und Zustände, mit Beispieldaten.
