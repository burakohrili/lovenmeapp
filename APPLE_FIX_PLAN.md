# LoveNMe iOS — Apple 4.3 Red Çözümü: Uygulama Brifingi

Sen kıdemli bir Flutter geliştiricisisin. Bu Flutter projesi (LoveNMe) Google Play'de
yayında ve çalışıyor; Apple App Store tarafı "Guideline 4.3(b) - Spam (doymuş dating
kategorisi)" gerekçesiyle reddediyor.

ÖNEMLİ TESPİT (doğrulanmış): Uygulamanın fonksiyonel motoru zaten MEKAN-TABANLI sosyal
keşiftir (check-in, harita, Mekan Muhtarı, elmas ekonomisi, ortak mekan karşılaşması).
Swipe/like sistemi zaten kaldırılmış. Reddi tetikleyen şeyler sadece YÜZEYSEL: dating
kostümü (kalp, "IT'S A MATCH", cinsiyet otomatik eşleştirme) + iOS metadata + birkaç ölü
kalıntı. Bu yüzden "baştan yazma" değil, "kostüm değiştirme" yapacağız.

## MUTLAK KURALLAR (ihlal etme)
1. Firestore koleksiyon ve alan adları DEĞİŞMEZ (matches, chat_requests, check_ins,
   likes, passes, super_likes, superChatsRemaining, dailyChatRequestsRemaining, isPremium
   vb.). Android yayında bu şemayı okuyor; adını değiştirmek mevcut kullanıcıları bozar.
2. IAP ürün ID'leri, fiyatları ve premium mantığı DEĞİŞMEZ. Sadece tanıtım METNİ değişir.
3. İstek-kabul (chat request) akışının MANTIĞI değişmez, sadece UI metinleri değişir.
4. Sadece şunlar değişir: UI metin/ikon/renk, cinsiyet mantığı, iOS metadata (Info.plist,
   pbxproj, Podfile), pubspec sürümü.
5. Her faz sonunda `flutter analyze` çalıştır, hata bırakma. Android'i bozacak hiçbir
   platform-özel kod ekleme.

---

## FAZ 0 — Teknik uyum (ITMS-90725 hatası)
- `ios/Runner.xcodeproj/project.pbxproj`: `IPHONEOS_DEPLOYMENT_TARGET = 13.0` olan 3 yeri
  `15.0` yap.
- `ios/Podfile`: `platform :ios, '14.0'` (veya benzeri) satırını `platform :ios, '15.0'` yap.
- `pubspec.yaml`: `version:` satırını `1.1.0+33` yap.
- NOT: Asıl ITMS-90725 çözümü Xcode 26 / iOS 26 SDK ile derlemektir (bunu kullanıcı Mac'te
  yapacak). Sen sadece yukarıdaki dosya değişikliklerini uygula.

---

## FAZ 1 — Cinsiyet eşleştirmesini kaldır (dating'in en sert sinyali)
Dosya: `lib/presentation/pages/onboarding/profile_setup_step7_page.dart`
- ~204-212 satırlardaki şu bloğu kaldır (cinsiyetten karşı cinsiyet türeten mantık):
  ```dart
  List<String> matchPreferences = [];
  if (profile.gender == 'Erkek') { matchPreferences = ['Kadın']; }
  else if (profile.gender == 'Kadın') { matchPreferences = ['Erkek']; }
  else { matchPreferences = ['Erkek', 'Kadın', 'Diğer']; }
  ```
  Yerine cinsiyet-nötr ata:
  ```dart
  List<String> matchPreferences = ['Erkek', 'Kadın', 'Diğer'];
  ```
- `matchPreferences` Firestore'a yazılmaya devam etsin (~276. satır). Alan adını DEĞİŞTİRME.
  (Bu alan kod tabanında hiçbir yerde okunmuyor; nötr yapmak keşfi bozmaz.)

Dosya: `lib/presentation/pages/onboarding/profile_setup_step1_page.dart`
- Cinsiyet seçimini ZORUNLU olmaktan çıkar: "Lütfen cinsiyet seçiniz" validasyonunu
  (~168. satır) kaldır veya "Atla/Belirtmek istemiyorum" seçeneği ekleyerek opsiyonel yap.
  Cinsiyet artık sadece opsiyonel gösterim bilgisidir.

---

## FAZ 2 — "Match" kostümünü "Mekan Bağlantısı"na çevir (sadece UI)
Dosya: `lib/presentation/widgets/match_animation_dialog.dart`
- ~118. satır: `"🎉 IT'S A MATCH! 🎉"` → `"📍 Ortak Mekanınız Var!"`
- ~182. satır: `Icons.favorite` (kalp) → `Icons.place`
- Tinder kırmızısı `Color(0xFFFA4458)` geçen yerleri marka mavi/yeşil tonuna çevir
  (örn. AppColors.primary kullan; kalp-kırmızı çağrışımını kaldır).
- Varsa kalp temalı Lottie (`chat_wink.json`) yerine nötr/pin animasyon kullan veya
  animasyonu kaldır.

Dosya: `lib/presentation/pages/messages/matches_page.dart`
- "Yeni Eşleşmeler" başlığını → "Mekan Bağlantıların" yap.
- Boş-durum ikonu `Icons.favorite_border` → `Icons.place`.
- Kullanıcıya görünen "eşleşme/eşleş" metinlerini "bağlantı/mekan bağlantısı" yap.

Genel: `lib/` altında kullanıcıya GÖRÜNEN string'lerde "eşleş", "match", "like", "süper
like", "flört" geçen yerleri "bağlantı / ortak mekan / tanışma isteği" diline çevir.
DİKKAT: Değişken adları, koleksiyon adları, alan adları ve `matchId` gibi teknik
isimleri DEĞİŞTİRME — sadece tırnak içindeki kullanıcı metinleri.

---

## FAZ 3 — Ortak check-in'i gerçek veriyle bağla (özgünlük kanıtı)
Dosya: `lib/presentation/pages/messages/providers/firebase_chat_provider.dart`
- ~152. satırda `commonCheckIns: 0` (hardcoded) kullanılıyor. Bunun yerine
  `lib/core/services/encounter_service.dart` içindeki `EncounterService.getTopEncounter()`
  ile hesaplanan GERÇEK ortak check-in sayısını geçir.
- Amaç: "Bu kişiyle X kez aynı mekanda karşılaştınız" bilgisinin gerçek olması. Bu additive
  bir iyileştirmedir, mevcut akışı bozmamalı. Null/0 durumlarını güvenli ele al.

---

## FAZ 4 — iOS metadata & izin temizliği
Dosya: `ios/Runner/Info.plist`
- ~87. satır `NSCameraUsageDescription`: "social dating experience" ibaresini kaldır:
  `LoveNMe, profil fotoğrafı çekmek ve mekanlardaki check-in'lerde fotoğraf paylaşmak için
   kamerayı kullanır.`
- ~69-70. satır `NSLocationAlwaysUsageDescription` anahtarını ve değerini TAMAMEN SİL
  (uygulama WhenInUse ile çalışıyor; Always arka plan takibi ek inceleme tetikliyor).
  `NSLocationWhenInUseUsageDescription` kalsın.
- Dosyaya kategori ekle:
  ```xml
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.social-networking</string>
  ```

Dosya: `lib/core/config/iap_config.dart`
- Premium paket özelliklerinde geçen "Günde 3 geri alma hakkı" gibi "geri alma/rewind"
  ibarelerini kaldır VEYA "Mekanda daha görünür ol" gibi mekan-odaklı bir ifadeyle değiştir.
  (rewind, dating/swipe çağrışımı; mağaza-yüzeyli metin.)
- Super Chat paketlerinde "fark yarat / Anında ilgi çek" gibi flört ifadelerini
  "tanışma isteğine kişisel not ekle / kalabalıkta öne çık" diline çevir.
- ÜRÜN ID, FİYAT, QUANTITY DEĞİŞTİRME — sadece title/description/features metinleri.

Dosya: `lib/widgets/super_chat_purchase_sheet.dart`
- ~178, ~204, ~542. satırlardaki "fark yarat / ilgi çek / dikkat çek" metinlerini mekan-
  sosyal dile çevir (yukarıyla tutarlı).

---

## FAZ 5 — Doğrulama görevi (rewind kontrolü) — SADECE RAPOR ET, KOD SİLME
- `lib/core/services/premium_service.dart` içindeki `canUseRewind()` ve `useRewind()`
  (~257-321) fonksiyonlarını ve çağrıldıkları yerleri incele. Swipe destesi olmadığı için
  "geri alma" özelliğinin fonksiyonel bir karşılığı var mı yok mu RAPOR ET. Eğer hiçbir
  yerde anlamlı kullanılmıyorsa, bana bildir (premium'dan kaldırma kararını kullanıcı verecek).

---

## SON KONTROLLER (bitince yap)
1. `flutter analyze` → 0 hata.
2. Kullanıcıya görünen hiçbir ekranda "IT'S A MATCH", kalp ikonu, "Süper Like",
   "Yeni Eşleşmeler" kalmadığını grep ile doğrula.
3. Onboarding'de cinsiyetin zorunlu OLMADIĞINI doğrula.
4. Firestore koleksiyon/alan adlarının ve IAP ürün ID'lerinin DEĞİŞMEDİĞİNİ doğrula
   (git diff ile kontrol et: bu isimler diff'te görünmemeli).
5. Değişiklik özetini ve değiştirdiğin tüm dosyaların listesini bana ver.

## YAPMA
- Firestore migration yapma, koleksiyon yeniden adlandırma.
- IAP/premium gelir mantığını değiştirme.
- Android-özel kod yollarını değiştirme.
- Yeni paket/dependency ekleme.
