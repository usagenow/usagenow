## 1.1.2

### Düzeltmeler

- Uygulama güncellendikten sonra mevcut widget’ların kurtarılması iyileştirildi. Seçili hesaplar ve yerleşim korunur.
- macOS bir sonraki yenilemeyi ertelese bile widget’ın son güncellemesinden bu yana geçen süre ilerlemeye devam eder.

## 1.1.1

### Fixed

- Sağlayıcı simgelerine geçerken veya uygulamayı bu modda başlatırken oluşan donma ve aşırı bellek kullanımı giderildi. Menü çubuğu simgeleri artık aynı boyutta; Antigravity beyaz kare olmadan gösteriliyor.

## 1.1.0

### Added

- Genel bakış — Bugün / 7 gün / 30 gün. Bu Mac’te kaydedilen yerel etkinlik. Geçmiş eksik olabilir.
- Hesap grupları — Gruplar görünümü değiştirir. Etkin hesaplar yenilenmeye ve bildirim göndermeye devam eder.
- Ayrı sağlayıcı simgeleri — Seçili sağlayıcı simgelerini ve kullanımlarını menü çubuğunda yan yana gösterin.
- Uyarlanabilir — Yenileme her hesabı, ağ durumunu, güç modunu ve ekran kilidini dikkate alır. Sunucunun bekleme süreleri her zaman korunur.
- Bakiye ve bütçeler — Bildirilen harcama bütçenin %80 ve %100’üne ulaştığında uyarır. Yalnızca uyarı verir. Bütçeler harcamayı engellemez. Sağlayıcının saat dilimi kullanılır; API fiyat tahminleri dâhil edilmez.
- MiniMax — MiniMax M Plan limitlerini izleyin.

## 1.0.0

### Added

- Uygulama ve araç takımlarında Kazakça, Özbekçe ve Türkçe: toplam on üç dil. Özbekçe çeviride Ö, Ğ, Ş ve Ç kullanılır.
- Sağlayıcı seçimiyle isteğe bağlı ilk kurulum. Atlanabilir ve Ayarlar’dan yeniden açılabilir. Mevcut seçimler korunur; ilk okuma kurulum bitirildikten veya atlandıktan sonra başlar.
- Sağlayıcı başına eşikler, bağımsız yenilenme bildirimleri ve Mac’in saat diliminde sessiz saatler. Atlanan uyarılar biriktirilmez; eski veriler uyarı oluşturmaz.
- İsteğe bağlı CLI: usagenow status ve usagenow status --json güvenli anlık görüntüyü güncellik bilgisiyle okur. Sağlayıcı isteği, kimlik doğrulama veya geçmiş dışa aktarımı yoktur. Ayarlar › Genel’den yüklenir.
- Uyanma sonrası yenileme, bildirim geçişi ve anlık görüntü uyumluluğu denetlenir. CLI yenilenen limitin yüzdesini kaldırır ve desteklenmeyen biçimleri reddeder.

## 0.9.0

### Added

- JetBrains AI (deneysel). JetBrains IDE’den yerel AI Assistant aylık kotası ve bildirilen yenilenme tarihi menü ve araç takımında. Aynı IDE’nin yeni olayı XML önbelleğini değiştirebilir; eski veriler zamanını korur. Kimlik bilgisi veya ağ isteği yoktur. Etkin abonelikle doğrulama bekleniyor.
- Kişisel araç takımları. Her biri için sağlayıcı ve hesap seçin veya UsageNow’u izlemek için boş bırakın. Yeniden adlandırma seçimi korur; silinen hesap sessizce başkasına geçmez.
- Büyük araç takımı. En fazla dört sağlayıcı veya hesap satırı, iki kota penceresi ve yenilenme zamanları. Küçükler gibi yalnızca güvenli anlık görüntüyü gösterir.
- Kota hızı. En kritik pencere için 15 dakikaya yayılan en az üç yeni ölçümden yerel grafik ve etiketli tahmin. Önbellek tekrarları, eski veriler, uzun aralar, yenilenmeler ve bilinmeyen sürelerde tahmin yoktur. Token sayıları kullanılmaz.
- İsteğe bağlı hizmet kesintileri. OpenAI, Claude, Cursor ve Copilot açık durum denetimleri varsayılan kapalı, önbelleği 10 dakika. Hesap veya kullanım verisi gönderilmez.
- Felemenkçe. Uygulama, araç takımları ve yerleşik yenilikler artık on dilde.
- Windsurf ve ElevenLabs simgeleri açık ve koyu görünüme uygun yenilendi.
- IDE olmadan Antigravity. IDE yanıtlamazsa uyumlu CLI 1.x (1.1.11+) resmi agy /usage raporu okunur. Ajan turu veya kimlik bilgisi erişimi yoktur; rapor beş dakika önbelleğe alınır. CLI 1.2.2 ile doğrulandı.

## 0.8.0

### Added

- Windsurf limitleri yerel önbellekten; Cursor, Copilot, Perplexity, ElevenLabs ve Z.ai açık bağlantılarla. ElevenLabs resmi API kullanır, diğer dördü deneyseldir.
- Cursor veya Perplexity’ye yalıtılmış geçici pencerede giriş veya elle çerez ekleme. Tarayıcı profilleri içe aktarılmaz.
- Kaydetmeden önce anahtar, token ve oturum doğrulanır. Elle ve otomatik yenileme hız sınırı bekleme süresine uyar.
- Portekizce, Japonca, Korece ve İbranice: uygulama dokuz dilde. Yenilikler çevrildi ve çevrimdışı çalışır.
- Menü için ek hesap seçimi. Hesap kredileri ve karakterler bugünkü yerel etkinlikten ayrıdır.

### Fixed

- Araç takımı sağlayıcı başına güncelliği izler, değişmeyen değerde bile yeni okuma zamanı yazar ve geri sayımı sürdürür. Limit yenilenince eski yüzde bilinmiyor olur.

## 0.7.2

### Fixed

- Rusça, Fransızca ve İspanyolcada sekme adları sığmadığından Gizlilik ve Hakkında açılmıyordu. Ayarlar penceresi artık genişler.

## 0.7.1

### Added

- Ayarlar › Genel › Dil’de macOS dili veya Almanca, İngilizce, İspanyolca, Fransızca, Rusça seçimi. Araç takımı aynı dili izler.
- Ek hesabı Ayarlar › Sağlayıcılar’daki … menüsünden yeniden adlandırma.

### Changed

- Ek hesap işlemleri tek menüde toplanarak her dilde satıra sığar.
- Boş veya eksik hesap klasörü gereksiz giriş istemeden belirtilir.

### Fixed

- Hesap eklenince diğer hesapların bir aylık oturumlarının yeniden okunması düzeltildi.

## 0.7.0

### Added

- Codex veya Claude Code için ikinci klasör; DeepSeek, Kimi, OpenRouter veya Ollama Cloud için ek anahtar. Her hesabın kendi bölümü ve verdiğiniz ad vardır. Asıl hesap adı veya e-posta okunmaz.
- Qwen Code yerel oturumlarından bugünkü tokenlar, istekler, modeller ve tahmini maliyet.
- Cline düzenleyici görevleri ve CLI’den tokenlar, API istekleri, modeller ve kaydettiği maliyet. İstemler, yanıtlar ve anahtarlar okunmaz.
- Grok Build oturum günlüklerinden bugünkü tokenlar, model çağrıları, modeller ve xAI maliyeti.
- Limit bildirmeyen sağlayıcılara araç takımında son iki hafta: miktarsız etkinlik şekli.
- Mac dilini izleyen Almanca, İspanyolca, Fransızca ve Rusça.
- Ayarlar › Hakkında’da Yenilikler: her sürümün değişiklikleri uygulamada.

### Changed

- Cline ve Grok Build için tahmin yerine aracın kaydettiği maliyet gösterilir.

## 0.6.1

### Added

- Limitin %20’si ve %5’i kalınca birer kez, uyarılan limit yenilenince bildirim. Varsayılan kapalı; Ayarlar › Bildirimler’den açılır.
- UsageNow’u her uygulamadan açan özel kestirme. Ayarlar › Menü çubuğu’nda kaydedilir. Ek izin gerekmez.

### Changed

- Maliyet tahmini Claude Sonnet 5.5 ve GPT-6.1 modellerini tanır.

### Fixed

- Yenileme sırasında Yeniden Dene, yeni API anahtarı veya yeni sağlayıcı işleminin yok sayılması düzeltildi.
- Antigravity dil sunucusu araması diğer sağlayıcıları bekletmez.
- Çok uzun oturum satırı belleğe alınmadan atlanır.

## 0.6.0

### Added

- Her sağlayıcıda son 30 gün: günlük sütun, aylık tokenlar, tahmini maliyet ve üst model. Üzerine gelerek günü görün. Ayarlar › Genel’den grafik kapatılır.
- OpenCode yerel veritabanından salt okunur tokenlar, istekler, modeller ve tahmini maliyet. İstemler ve yanıtlar okunmaz.
- Qoder kayıtlarından bugünkü harcanan krediler ve yanıtlar. Kimlik bilgileri açılmaz.
- Ollama Cloud (deneysel): kendi Cloud API anahtarınızla oturum ve haftalık limitler.
- Menü ve araç takımında limitleri Kalan veya Kullanılan olarak gösterme.
- Kiro, Warp ve Qoder için araç takımında krediler.
- Ayarlar › Hakkında’daki sorun raporunu önce görün, sonra GitHub veya e-postayla kendiniz gönderin. Ad, yol, anahtar veya istem içermez.

### Changed

- Menü penceresi daha opak ve küçük ekrandan taşmak yerine kaydırılır.
- Ayarlar › Sağlayıcılar dizüstü ekranına sığar.
- Maliyet tahmini Claude Opus 5.5 ve GPT-6 gibi yeni modelleri tanır.
- Bir aylık oturumları okuma birkaç kat hızlı ve daha az bellek kullanır.

### Fixed

- ChatGPT 26.9’da Codex CLI taşındıktan sonra limitlerin yenilenmemesi düzeltildi.
- Eski Claude limitleri artık yenileme yolunu gösterir; eski yüzde güncel görünmez.
- Araç takımı yeni uygulama verisini okuyup UsageNow’u açmanızı istemez.
- Codex app-server erken kapanınca uygulamanın sessizce çıkması düzeltildi.

## 0.5.0

### Added

- Kiro: Mac’teki aylık kredi limiti, yenilenme, bugünkü kredi ve istemler. Kiro’ya istek veya kimlik bilgisi okuma yoktur.
- Warp: yerel veritabanından salt okunur bugünkü ajan istekleri, krediler ve model tokenları.
- DeepSeek, Kimi, OpenRouter: kendi API anahtarınızla resmi bakiye ve harcama. Anahtar Anahtar Zinciri’nde, yalnızca ilgili sağlayıcıya gider. Bu sürümde gerçek hesapla henüz doğrulanmadı.

## 0.4.0

### Added

- Her sağlayıcıda API fiyatlarıyla token maliyet tahmini, önbellek kendi fiyatıyla. Ölçek göstergesidir, fatura değil; abonelik token başına ücret almaz.
- Uygulama yalnızca kendi imzalı güncellemelerini denetleyip yükler. Denetleme size ait veri göndermez. 0.3.0’dan bir kez 0.4.0 elle yüklenir.

### Changed

- Yenilemede simge dönmez, okun çevresinde ilerleme yayı gösterilir.
- Menü çubuğu yüzdesi yanındaki simgelere uygun boyuttadır.

## 0.3.0

### Added

- Antigravity: çalışan uygulamadan model grubu başına 5 saatlik, haftalık limitler ve plan. Kimlik bilgisi yok, yalnızca 127.0.0.1.
- Gemini CLI yerel oturumlarından tokenlar, istekler ve modeller. Kota bildirilmediği için gösterilmez.
- Codex, Claude Code ve Gemini CLI için bugünkü modeller listesi, en etkin önce.
- Team planları: Claude Team · Premium gibi koltuğu; Codex Team, Business ve Enterprise gösterir.
- Antigravity ve Gemini CLI menü modları.
- Ayarlar’da sürükleyerek sıralama; menü ve araç takımı aynı sırayı izler.
- Cursor ve GitHub Copilot yakında listesinde.

### Changed

- Üç ve üzeri sağlayıcıda orta araç takımında birer satır, küçükte limite en yakın en fazla üç sağlayıcı.
- Yeni sağlayıcı güncellemede bir kez açılır. Kapattıklarınız kapalı kalır.

### Fixed

- Claude limitleri artık macOS parolasını istemez ve Claude Code çalıştırılınca kendiliğinden geri gelir.
- Siz yokken yenilenen Claude penceresi kaybolmaz; ulaşılan limitler giriş olmadan da görünür.
- Son Claude limitleri uygulama kapanınca veya güncellenince korunur.

## 0.2.0

### Added

- Gerçek veriler: Codex limitleri, yenilenmeleri ve planı resmi app-server’dan; Codex ve Claude Code tokenları, istekleri ve son modeli yerel oturumlardan.
- Küçük ve orta masaüstü araç takımları.
- Claude Code limitleri deneysel ve varsayılan kapalı.
- Codex ve Claude Code ayrı açılıp kapatılabilir.
- Menü modları: yalnızca simge, en kritik kullanım veya tek sağlayıcı.
- Açık, koyu veya sistem görünümü.

### Changed

- Kullanım “%58 kaldı” olarak gösterilir; kullandıkça çubuk küçülür.
- Pencereler sağlayıcının bildirdiği gibi gösterilir; eksik pencere uydurulmaz.
- Limit okunamazsa son değerler bir gün eski etiketi ve kısa nedeni ile korunur.

## 0.1.0

### Added

- Yerel menü uygulaması, ayarları ve durumları örnek verilerle çalışır.
