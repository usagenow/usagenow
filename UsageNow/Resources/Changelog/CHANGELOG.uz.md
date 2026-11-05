## 1.1.2

### Tuzatişlar

- Ilova yangilangandan keyin vidjetlarni tiklaş yaxşilandi. Tanlangan hisoblar va joylaşuv saqlanadi.
- macOS keyingi yangilanişni keçiktirsa ham, vidjetning oxirgi yangilanişidan beri ötgan vaqt körsatkiçi yangilanib turadi.

## 1.1.1

### Fixed

- Provayder ikonalarini yoqişda yoki ilovani şu rejimda oçişda qotib qoliş va xotira sarfining ortib ketişi tuzatildi. Menyu qatoridagi ikonalar endi bir xil ölçamda; Antigravity oq kvadratsiz körsatiladi.

## 1.1.0

### Added

- Umumiy köriniş — Bugun / 7 kun / 30 kun. Şu Mac’da yozilgan mahalliy faollik. Tarix töliq bölmasligi mumkin.
- Hisoblar töplamlari — Töplamlar körinişni özgartiradi. Yoqilgan hisoblar yangilaniş va bildirişlarni davom ettiradi.
- Provayderlar uçun alohida belgilar — Tanlangan provayder belgilarini va sarfini menyu satrida yonma-yon körsating.
- Moslaşuvçan — Yangilaş har bir hisob, tarmoq, quvvat rejimi va ekran qulfini hisobga oladi. Server kutiş vaqti doim saqlanadi.
- Balans va budjetlar — Bildirilgan sarf budjetning 80% va 100% iga yetganda ogohlantiriş. Faqat ogohlantirişlar. Budjet sarfni töxtatmaydi. Provayder vaqt mintaqasi qöllanadi; API narxi taxminlari hisoblanmaydi.
- MiniMax — MiniMax M Plan limitlarini kuzating.

## 1.0.0

### Added

- Dastur va vidjetlarga qozoqça, özbekça va turkça qöşildi — jami ön uç til. Özbekça tarjimada Ö, Ğ, Ş va Ç işlatiladi.
- Provayder tanlovli ixtiyoriy birinçi sozlaş. Uni ötkazib yuboriş yoki Sozlamalardan qayta oçiş mumkin. Mavjud tanlovlar saqlanadi; birinçi öqiş sozlaş tugagandan yoki ötkazilgandan keyin başlanadi.
- Har bir provayder uçun alohida ogohlantiriş çegaralari, yangilaniş bildirişlari va Mac vaqt mintaqasidagi sokin soatlar. Ötkazilgan bildirişlar yiğilmaydi; eski ma’lumotlar ogohlantiriş yaratmaydi.
- Ixtiyoriy CLI: usagenow status va usagenow status --json xavfsiz snapshot va yangilaniş vaqtini öqiydi. Provayder sörovlari, kiriş va tarix eksporti yöq. Sozlamalar › Umumiy bölimida örnatiladi.
- Uyqudan keyin yangilaş, bildirişlarni köçiriş va snapshot mosligi tekşirildi. CLI yangilangan limit foizini olib taşlaydi va qöllanmaydigan formatni rad etadi.

## 0.9.0

### Added

- JetBrains AI (tajribaviy). JetBrains IDE’dagi mahalliy AI Assistant oylik kvotasi va bildirilgan yangilaniş sanasi menyu va vidjetda. Şu IDE’ning yangi hodisasi XML keşini almaştiradi; eski ma’lumot asl vaqtini saqlaydi. Kiriş ma’lumotlari va tarmoq sörovlari yöq. Faol obuna bilan tekşiruv hali kerak.
- Şaxsiy vidjetlar. Har bir vidjetga provayder va hisoblarni tanlang yoki UsageNow tanloviga ergaşiş uçun böş qoldiring. Nom özgarganda tanlov saqlanadi; öçirilgan hisob boşqasiga almaşmaydi.
- Katta vidjet. Törttagaça provayder yoki hisob qatori, ikkita kvota davri va yangilaniş vaqti. Boşqa ölçamlar kabi faqat xavfsiz snapshot körsatadi.
- Kvota sur’ati. Eng kam qolgan davr uçun 15 daqiqani qamragan kamida uçta yangi ölçovdan mahalliy grafik va belgilangan taxmin. Keş, eski ma’lumot, uzoq uziliş, yangilaniş yoki noma’lum davrda taxmin berilmaydi. Token soni işlatilmaydi.
- Xizmat uzilişlarining ixtiyoriy körsatkiçi. OpenAI, Claude, Cursor va Copilot oçiq holati tekşiruvi dastlab öçirilgan, keşi 10 daqiqa. Hisob va sarf ma’lumotlari yuborilmaydi.
- Niderland tili. Dastur, vidjetlar va içki yangiliklar endi ön tilda.
- Windsurf va ElevenLabs belgilari yangilandi, oç va töq körinişlarga moslandi.
- Antigravity IDE’siz. IDE javob bermasa, mos CLI 1.x (1.1.11+) rasmiy agy /usage hisoboti öqiladi. Agent aylanişi va kiriş ma’lumotlarini öqiş yöq; hisobot beş daqiqa keşlanadi. CLI 1.2.2’da tekşirilgan.

## 0.8.0

### Added

- Windsurf limitlari mahalliy keşdan; Cursor, Copilot, Perplexity, ElevenLabs va Z.ai alohida ulanişlar orqali. ElevenLabs rasmiy API işlatadi, qolgan törttasi tajribaviy.
- Cursor yoki Perplexity’ga alohida vaqtinça oynada kiriş yoki cookie faylini qölda kiritiş. Brauzer profillari import qilinmaydi.
- Saqlaşdan oldin kalit, token va seans tekşiriladi. Qölda va avtomatik yangilaş rate limit kutiş muddatiga amal qiladi.
- Portugal, yapon, koreys va ivrit: dastur töqqiz tilda. Yangiliklar tarjima qilingan va oflayn işlaydi.
- Menyuga qöşimça hisobni tanlaş. Hisob kreditlari va belgilari bugungi mahalliy faollikdan alohida.

### Fixed

- Vidjet har bir provayderning yangiligini kuzatadi, özgarmagan qiymatga ham yangi öqiş vaqtini yozadi va sanaşni davom ettiradi. Limit yangilanganda eski foiz noma’lum böladi.

## 0.7.2

### Fixed

- Rus, fransuz va ispan tillarida bölim nomlari siğmagani uçun Maxfiylik va Dastur haqida oçilmasdi. Sozlamalar oynasi endi kengayadi.

## 0.7.1

### Added

- Sozlamalar › Umumiy › Til bölimida macOS tili yoki nemis, ingliz, ispan, fransuz, rus tillarini tanlaş. Vidjet ham şu tilni işlatadi.
- Qöşimça hisob nomini Sozlamalar › Provayderlardagi … menyusidan özgartiriş.

### Changed

- Qöşimça hisob amallari bitta menyuga yiğilib, har tilda qatorga siğadi.
- Böş yoki yöq hisob jildi örinsiz kiriş söramasdan körsatiladi.

### Fixed

- Hisob qöşilganda boşqa hisoblarning bir oylik seanslari qayta öqilişi tuzatildi.

## 0.7.0

### Added

- Codex yoki Claude Code uçun ikkinçi jild, DeepSeek, Kimi, OpenRouter yoki Ollama Cloud uçun qöşimça kalit. Har bir hisobning öz bölimi va özingiz qöygan nomi bor. Asl hisob nomi yoki poçtasi öqilmaydi.
- Qwen Code mahalliy seanslaridan bugungi tokenlar, sörovlar, modellar va taxminiy xarajat.
- Cline muharrir vazifalari va CLI’dan tokenlar, API sörovlari, modellar va özi yozgan xarajat. Sörovlar, javoblar va kalitlar öqilmaydi.
- Grok Build seans jurnallaridan bugungi tokenlar, model çaqiruvlari, modellar va xAI bildirgan xarajat.
- Limit bermaydigan provayderlarga vidjetda oxirgi ikki hafta: aniq sonlarsiz faollik şakli.
- Mac tiliga mos nemis, ispan, fransuz va rus tillari.
- Sozlamalar › Dastur haqidadagi yangiliklar: har bir versiya özgarişi dasturda.

### Changed

- Cline va Grok Build uçun taxmin örniga vosita yozgan xarajat körsatiladi.

## 0.6.1

### Added

- Limitning 20% va 5% qolganda bir martadan, ogohlantirilgan limit yangilanganda bildiriş. Dastlab öçirilgan; Sozlamalar › Bildirişlarda yoqiladi.
- UsageNow’ni istalgan dasturdan oçadigan şaxsiy tugmalar birikmasi. Sozlamalar › Menyu panelida yoziladi. Qöşimça ruxsat kerak emas.

### Changed

- Xarajat taxmini Claude Sonnet 5.5 va GPT-6.1 modellarini biladi.

### Fixed

- Yangilaş paytida Qayta uriniş, yangi API kaliti yoki yangi provayder amali e’tiborsiz qolişi tuzatildi.
- Antigravity til serverini qidiriş boşqa provayderlarni töxtatmaydi.
- Juda uzun seans qatori xotiraga yuklanmay ötkaziladi.

## 0.6.0

### Added

- Har bir provayderda oxirgi 30 kun: kunlik ustun, oylik tokenlar, taxminiy xarajat va asosiy model. Işora qilib kunni köring. Sozlamalar › Umumiyda grafik öçiriladi.
- OpenCode mahalliy bazasidan faqat öqiş bilan tokenlar, sörovlar, modellar va taxminiy xarajat. Sörov va javob öqilmaydi.
- Qoder transkriptlaridan bugungi sarflangan kreditlar va javoblar. Kiriş ma’lumotlari oçilmaydi.
- Ollama Cloud (tajribaviy) — şaxsiy Cloud API kaliti bilan seans va haftalik limitlar.
- Menyu va vidjetda limitlarni Qolgan yoki Işlatilgan tarzida körsatiş.
- Kiro, Warp va Qoder uçun vidjetda kreditlar.
- Sozlamalar › Dastur haqidadagi muammo hisobotini avval körib, keyin GitHub yoki xat orqali özingiz yuboring. Nom, yöl, kalit yoki sörov yöq.

### Changed

- Menyu oynasining şaffofligi kamaytirildi va kiçik ekrandan çiqiş örniga aylantiriladi.
- Sozlamalar › Provayderlar noutbuk ekraniga siğadi.
- Xarajat taxmini Claude Opus 5.5 va GPT-6 kabi yangi modellarni biladi.
- Bir oylik seanslarni öqiş bir neça baravar tez va xotirani ança kam işlatadi.

### Fixed

- ChatGPT 26.9 içidagi Codex CLI joyi özgargandan keyin limitlar yangilanmasligi tuzatildi.
- Eski Claude limitlari endi yangilaş usulini körsatadi; eski foiz yangi deb körinmaydi.
- Vidjet yangiroq dastur ma’lumotlarini öqib, UsageNow’ni oçişni söramaydi.
- Codex app-server erta yopilganda dasturning jim çiqişi tuzatildi.

## 0.5.0

### Added

- Kiro — Mac’da yozilgan oylik kredit limiti, yangilaniş, bugungi kreditlar va sörovlar. Kiro’ga sörov va kiriş ma’lumotlarini öqiş yöq.
- Warp — mahalliy bazadan faqat öqiş bilan bugungi agent sörovlari, kreditlar va model tokenlari.
- DeepSeek, Kimi, OpenRouter — şaxsiy API kaliti bilan rasmiy balans va xarajat. Kalit Keychain’da va faqat öz provayderiga yuboriladi. Şu relizda haqiqiy hisobda hali tekşirilmagan.

## 0.4.0

### Added

- Har bir provayderda e’lon qilingan API narxida token qiymati taxmini, keş öz narxida. Bu kölam körsatkiçi, hisob emas; obuna tokenga haq olmaydi.
- Dastur faqat öz imzosi bor yangilanişlarni tekşirib örnatadi. Tekşiruv siz haqingizda ma’lumot yubormaydi. 0.3.0’dan bir marta 0.4.0 qölda örnatiladi.

### Changed

- Yangilaşda belgi aylanmay, öq atrofida jarayon yoyi körsatiladi.
- Menyu panelidagi foiz yonidagi belgilarga mos ölçamda.

## 0.3.0

### Added

- Antigravity — işlayotgan dasturdan model guruhining 5 soatlik, haftalik limiti va tarifi. Kiriş ma’lumotlari yöq, faqat 127.0.0.1.
- Gemini CLI mahalliy seanslaridan tokenlar, sörovlar va modellar. Kvota berilmagani uçun körsatilmaydi.
- Codex, Claude Code va Gemini CLI uçun bugungi modellar röyxati, eng faoli birinçi.
- Team tariflari: Claude örin turini, masalan Team · Premium; Codex Team, Business va Enterprise körsatadi.
- Antigravity va Gemini CLI menyu rejimlari.
- Sozlamalarda provayderni sudrab tartiblaş; menyu va vidjet şu tartibda yuradi.
- Cursor va GitHub Copilot tez kunda qöşiladiganlar röyxatida.

### Changed

- Uç yoki undan köp provayderda örta vidjetda har biri bitta qator, kiçik vidjetda eng kam qolgan uçtagaça provayder.
- Yangi provayder yangilanişda bir marta yoqiladi. Oldin öçirilganlari öçirilgan qoladi.

### Fixed

- Claude limitlari endi macOS parolini söramaydi va Claude Code işga tuşirilgandan keyin özi qaytadi.
- Siz yöqda yangilangan Claude davri yöqolmaydi; yetilgan limitlar kirişsiz ham körinadi.
- Sönggi Claude limitlari dastur yopilsa yoki yangilansa saqlanadi.

## 0.2.0

### Added

- Haqiqiy ma’lumotlar: Codex limiti, yangilanişi va tarifi rasmiy app-server’dan; Codex va Claude Code tokenlari, sörovlari va sönggi modeli mahalliy seanslardan.
- Kiçik va örta iş stoli vidjetlari.
- Claude Code limitlari tajribaviy va dastlab öçirilgan.
- Codex va Claude Code alohida yoqiladi va öçiriladi.
- Menyu rejimlari: faqat belgi, eng kam qolgan limit yoki bitta provayder.
- Oç, töq yoki tizim körinişi.

### Changed

- Sarf «58% qoldi» tarzida, sarflangan sari çiziq qisqaradi.
- Davrlar provayder bildirganidek körsatiladi; yöq davr öylab topilmaydi.
- Limit öqilmasa, sönggi qiymatlar bir kun eski deb belgilanib, qisqa sabab bilan saqlanadi.

## 0.1.0

### Added

- Nativ menyu dasturi, sozlamalari va holatlari misol ma’lumotlar bilan işlaydi.
