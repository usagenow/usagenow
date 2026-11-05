# Wijzigingen

## 1.1.1

### Fixed

- Vastlopen en sterk oplopend geheugengebruik bij het inschakelen van providerpictogrammen of het starten in deze modus zijn verholpen. De pictogrammen in de menubalk hebben nu hetzelfde formaat; Antigravity verschijnt zonder wit vierkant.

## 1.1.0

### Added

- Overzicht — Vandaag / 7 dagen / 30 dagen. Lokale activiteit op deze Mac. De geschiedenis kan onvolledig zijn.
- Accountgroepen — Groepen wijzigen de weergave. Ingeschakelde accounts blijven vernieuwen en meldingen sturen.
- Afzonderlijke providersymbolen — Toon de geselecteerde providersymbolen en hun gebruik naast elkaar in de menubalk.
- Adaptief — Vernieuwing houdt rekening met elk account, netwerk, energiemodus en schermvergrendeling. Wachttijden van de server gelden altijd.
- Saldo en budgetten — Budgetwaarschuwingen bij 80% en 100% van de gemelde uitgaven. Alleen waarschuwingen. Budgetten blokkeren geen uitgaven. De tijdzone van de provider geldt; API-prijsschattingen tellen niet mee.
- MiniMax — Volg de limieten van MiniMax M Plan.

## 1.0.0

### Added

- Kazachs, Oezbeeks en Turks in app en widgets: dertien talen. Oezbeeks gebruikt Ö, Ğ, Ş en Ç.
- Optionele eerste configuratie met providerkeuze. Overslaan en opnieuw openen via Instellingen zijn mogelijk. Bestaande installaties behouden hun keuzes; de eerste lezing begint na afronden of overslaan.
- Meldingsdrempels per provider, afzonderlijke resetmeldingen en stille uren in de tijdzone van de Mac. Overgeslagen meldingen worden niet opgespaard; oude gegevens veroorzaken geen waarschuwing.
- Optionele CLI: usagenow status en usagenow status --json lezen de veilige momentopname met actualiteit. Geen providerverzoeken, aanmelding of geschiedenisexport. Installeer via Instellingen › Algemeen.
- Vernieuwen na ontwaken en controles voor meldingsmigratie en snapshotcompatibiliteit. De CLI verwijdert percentages na resets en weigert onbekende formaten.

## 0.9.0

### Added

- **JetBrains AI (experimenteel).** Lokale AI Assistant-limieten uit je JetBrains-IDE, met de gemelde aanvuldatum, in de menubalk en widgets. Oude waarden behouden hun oorspronkelijke tijdstip. Geen inloggegevens of netwerkverzoeken. Controle met een actieve AI Assistant moet nog plaatsvinden.
- **Persoonlijke widgets.** Kies per widget providers en accounts of laat de selectie leeg om UsageNow te volgen. Hernoemen behoudt de keuze; een verwijderd account wordt nooit stilzwijgend vervangen.
- **Grote widget.** Tot vier gedetailleerde provider- of accountregels met twee limietvensters en hun resettijden. De widget toont uitsluitend de gefilterde momentopname.
- **Verbruikstempo.** Een lokale grafiek en duidelijk gemarkeerde schatting voor het meest kritieke venster, op basis van minimaal drie verse metingen over 15 minuten. Gecachete herhalingen, verouderde gegevens, lange onderbrekingen, resets en onbekende vensterlengtes leveren geen prognose op. Tokenaantallen worden nooit gebruikt.
- **Optionele storingsmeldingen.** Openbare statuspagina’s van OpenAI, Claude, Cursor en GitHub Copilot, standaard uit en tien minuten gecachet. Dienststatus staat los van je account en limieten; account- en verbruiksgegevens worden niet verstuurd.
- **Nederlands.** App, widgets en ingebouwde release-informatie: UsageNow ondersteunt nu tien talen.
- **Vernieuwde Windsurf- en ElevenLabs-pictogrammen.** De juiste providerafbeeldingen, geschikt voor lichte en donkere weergave.

- **Antigravity zonder IDE.** Als de IDE niet antwoordt, leest UsageNow het officiële `agy /usage`-rapport uit compatibele CLI 1.x-versies vanaf 1.1.11. Geen agentbeurt en geen toegang tot inloggegevens door UsageNow; rapporten worden vijf minuten gecachet. Getest met CLI 1.2.2.

## 0.8.0

### Added

- Windsurf-limieten uit de lokale abonnements-cache; Cursor, GitHub Copilot, Perplexity, ElevenLabs en Z.ai via expliciete verbindingen. ElevenLabs gebruikt de officiële API; de andere vier verbonden diensten zijn experimenteel.
- Log in bij Cursor of Perplexity via een geïsoleerd tijdelijk venster of voeg handmatig een sessiecookie toe. Bestaande browserprofielen worden niet geïmporteerd.
- Controleren en opslaan verifieert sleutels, tokens en sessies vóór het opslaan. Automatisch en handmatig vernieuwen respecteren wachttijden na een verzoeklimiet.
- Portugees, Japans, Koreaans en Hebreeuws: de app ondersteunt nu negen talen. De release-informatie is vertaald en werkt offline.
- Kies een toegevoegd account voor de menubalk. Accountcredits en tekens blijven gescheiden van de lokale activiteit van vandaag.

### Fixed

- Widgets houden de actualiteit per provider bij, slaan nieuwe leestijden op bij ongewijzigde waarden en laten aftellingen doorlopen. Oude percentages worden onbekend na een limietreset.

## 0.7.2

### Fixed

- Privacy en Over konden niet worden geopend in het Russisch, Frans of Spaans: de tabtitels pasten niet in het venster. Instellingen wordt nu breed genoeg.

## 0.7.1

### Added

- Kies de taal via Instellingen › Algemeen › Taal: volg macOS of kies Duits, Engels, Spaans, Frans of Russisch. De widget volgt dezelfde keuze.
- Hernoem een toegevoegd account via het …-menu in Instellingen › Providers.

### Changed

- De acties van een toegevoegd account staan in één menu, zodat de rij in elke taal past.
- Een lege of ontbrekende accountmap wordt als zodanig gemeld, zonder onnodig om inloggen te vragen.

### Fixed

- Het toevoegen van een account liet de andere toegevoegde accounts hun hele maand aan sessies opnieuw lezen.

## 0.7.0

### Added

- Meerdere accounts: een tweede Codex- of Claude Code-map of een extra API-sleutel voor DeepSeek, Kimi, OpenRouter of Ollama Cloud. Elk krijgt een eigen overzicht met een gekozen naam, zoals ‘Codex · Werk’. UsageNow leest nooit de eigen accountnaam of het e-mailadres.
- Qwen Code: tokens, verzoeken, modellen en geschatte kosten van vandaag, uit de lokale sessies van Qwen Code.
- Cline: tokens, API-verzoeken, modellen en vastgelegde kosten van vandaag, uit Cline-taken in je editor en de CLI. Prompts, antwoorden en sleutels worden niet uitgelezen.
- Grok Build: tokens, modelaanroepen, modellen en door xAI gemelde kosten van vandaag, uit lokale sessielogboeken.
- De afgelopen twee weken in de widget voor providers zonder limieten: alleen de vorm van je activiteit, geen aantallen.
- UsageNow in het Duits, Spaans, Frans en Russisch, volgens de taal van je Mac.
- Wat is er nieuw? in Instellingen › Over: wijzigingen van elke versie, ingebouwd in de app.

### Changed

- Bij Cline en Grok Build wordt de door de tool vastgelegde prijs getoond, geen schatting.

## 0.6.1

### Added

- Meldingen wanneer 20% en 5% van een limiet over is, elk één keer, en wanneer een eerder gemelde limiet reset. Standaard uit; inschakelen via Instellingen › Meldingen.
- Een eigen sneltoets om UsageNow vanuit elke app te openen, in te stellen via Instellingen › Menubalk. Geen extra machtigingen nodig.

### Changed

- De kostenschatting kent Claude Sonnet 5.5 en GPT-6.1.

### Fixed

- Opnieuw proberen, een nieuw toegevoegde API-sleutel of een net ingeschakelde provider kon tijdens een lopende vernieuwing worden genegeerd.
- Antigravity houdt andere providers niet meer op tijdens het zoeken naar de taalserver.
- Een zeer lange sessieregel wordt overgeslagen zonder hem volledig in het geheugen te laden.

## 0.6.0

### Added

- De afgelopen 30 dagen onder elke provider: een balk per dag, tokens, geschatte kosten en het meest gebruikte model. Beweeg over een balk voor dagdetails. Grafieken zijn uit te schakelen via Instellingen › Algemeen.
- OpenCode: tokens, verzoeken, modellen en geschatte kosten van vandaag, alleen-lezen uit de lokale database. Prompts en antwoorden worden niet uitgelezen.
- Qoder: credits van vandaag en de bijbehorende antwoorden uit lokale transcripties. De Qoder-aanmelding wordt nooit geopend.
- Ollama Cloud (experimenteel): sessie- en weeklimieten met je eigen Cloud-API-sleutel.
- Toon limieten als Resterend of Gebruikt in het uitklapvenster, de menubalk en de widget.
- Credits in de widget voor Kiro, Warp en Qoder.
- Een probleem melden via Instellingen › Over: bekijk eerst het hele rapport en verstuur daarna zelf een GitHub-issue of e-mail. Geen namen, paden, sleutels of prompts.

### Changed

- Het menubalkvenster is minder transparant en scrolt in plaats van buiten een klein scherm te vallen.
- Instellingen › Providers past op een laptopscherm.
- De kostenschatting kent de nieuwste modellen, waaronder Claude Opus 5.5 en GPT-6.
- Een maand sessiebestanden lezen is meerdere keren sneller en gebruikt veel minder geheugen.

### Fixed

- Codex-limieten stopten met vernieuwen vanaf ChatGPT 26.9, waarin de ingebouwde Codex-CLI was verplaatst.
- Verouderde Claude-limieten leggen nu uit hoe je ze vernieuwt, zodat een oud percentage niet actueel lijkt.
- De widget leest gegevens van een nieuwere appversie in plaats van te vragen UsageNow te openen.
- UsageNow kon onverwacht stoppen als de Codex-app-server vroegtijdig afsloot.

## 0.5.0

### Added

- Kiro: maandelijkse creditlimiet, resetdatum en credits en prompts van vandaag uit lokale Kiro-gegevens. Geen verzoek naar Kiro en geen Kiro-toegangsgegevens.
- Warp: agentverzoeken, credits en tokens per model van vandaag, alleen-lezen uit de lokale database.
- DeepSeek, Kimi en OpenRouter: saldo’s en uitgaven via hun officiële API’s met je eigen API-sleutel. Die blijft in Sleutelhanger en gaat alleen naar die provider. Nog niet met live accounts geverifieerd.

## 0.4.0

### Added

- Wat de tokens van vandaag zouden kosten: een schatting bij de totalen van elke provider tegen gepubliceerde API-tarieven, met cachetarieven voor gecachete tokens. Een indicatie, geen factuur: abonnementen rekenen niet per token.
- Updates in de app. UsageNow controleert en installeert alleen updates met zijn eigen handtekening. De controle verstuurt geen persoonlijke gegevens. Vanaf 0.3.0 moet je één keer handmatig 0.4.0 installeren.

### Changed

- Vernieuwen toont een voortgangsboog rond de pijl in plaats van een draaiend pictogram.
- Het percentage in de menubalk is afgestemd op de pictogrammen ernaast.

## 0.3.0

### Added

- Antigravity: 5-uurs- en weeklimieten per modelgroep en het abonnement, uit de actieve Antigravity-app. Geen toegangsgegevens en niets buiten 127.0.0.1.
- Gemini CLI: tokens, verzoeken en modellen uit lokale sessies. Gebruikslimieten worden niet gemeld en dus niet getoond.
- Activiteit per model: een lijst Modellen vandaag voor Codex, Claude Code en Gemini CLI, meest actieve eerst.
- Team-abonnementen: Claude toont het type licentie, bijvoorbeeld Team · Premium; Codex toont Team, Business en Enterprise.
- Menubalkstanden voor Antigravity en Gemini CLI.
- Versleep providers in Instellingen; het uitklapvenster en de widget volgen de volgorde.
- Cursor en GitHub Copilot staan onder Binnenkort.

### Changed

- Vanaf drie providers toont de middelgrote widget een rij per provider en de kleine widget maximaal drie, met de meest kritieke limieten eerst.
- Een provider die met een update wordt toegevoegd, start één keer ingeschakeld. Zelf uitgeschakelde providers blijven uit.

### Fixed

- Claude-gebruikslimieten vragen niet meer om je inlogwachtwoord en komen vanzelf terug nadat je Claude Code start.
- Een Claude-limietvenster dat tijdens je afwezigheid is gereset blijft zichtbaar. Bereikte limieten verschijnen zonder aanmelding.
- De laatst bekende Claude-limieten blijven bewaard na afsluiten of bijwerken van de app.

## 0.2.0

### Added

- Echte gegevens: Codex-limieten, resettijden en abonnement via de officiële Codex-app-server; tokens, verzoeken en het laatste model van Codex en Claude Code uit lokale sessies.
- Bureaubladwidgets in klein en middelgroot formaat.
- Claude Code-gebruikslimieten: experimenteel en standaard uitgeschakeld.
- Codex en Claude Code zijn afzonderlijk in en uit te schakelen.
- Menubalkstanden: alleen pictogram, meest kritieke verbruik of één provider.
- Lichte, donkere of systeemweergave.

### Changed

- Verbruik wordt getoond als resterend tegoed — ‘58% over’ — en balken worden kleiner naarmate je meer gebruikt.
- Limietvensters verschijnen precies zoals de provider ze meldt. Ontbrekende vensters worden nooit verzonnen.
- Als limieten niet kunnen worden gelezen, blijven de laatste waarden een dag staan, als verouderd gemarkeerd met een korte reden.

## 0.1.0

### Added

- De native menubalk-app, instellingen en toestanden, met voorbeeldgegevens.
