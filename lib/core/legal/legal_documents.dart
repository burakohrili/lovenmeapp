// lib/core/legal/legal_documents.dart

/// Kullanım Şartları ve Gizlilik Politikası — TEK KAYNAK.
///
/// NEDEN BURADA:
/// Bu metinler daha önce İKİ ayrı dosyada (kayıt ekranı ve ayarlar ekranı)
/// kopyalanmış hâlde duruyordu ve zamanla birbirinden ayrışmışlardı: farklı
/// veri sorumlusu, farklı iletişim adresi, farklı yürürlük tarihi. Dahası
/// Şartlar "Google Ads/AdMob"ı sağlayıcı olarak sayarken Gizlilik Politikası
/// "üçüncü taraf reklam hizmetleri bulunmamaktadır" diyordu — Apple'ın App
/// Privacy formu bu metinlerle karşılaştırılır.
///
/// 30.08.2026 düzeltmeleri:
///  - Var olmayan sağlayıcı (AdMob) ve var olmayan giriş yöntemi
///    (Apple/Google ile giriş) kaldırıldı
///  - Premium fayda listesinden kaldırılmış özellik çıkarıldı
///    ("check-in yapmadan kişileri görebilme" — mevcudiyet kapısıyla kaldırıldı)
///  - Dating dönemi sözlüğü (Super Like) temizlendi
///  - Gizlilik Politikası 2 işleyici sayıyordu; gerçekte kullanılan 10 işleyici
///    listelendi (KVKK Md. 10 / GDPR Md. 13(1)(e) aydınlatma yükümlülüğü)
///
/// ⚠️ ONAY BEKLİYOR: Veri sorumlusu unvanı ve iletişim adresi iki belgede
/// farklıydı (Burak Ohrili / Noesis Social ve lovenmeapp@gmail.com /
/// support@lovenme.app). Tutarlılık için Şartlar'daki değerlerde birleştirildi;
/// hangisinin doğru tüzel kişi olduğunu teyit edip burada güncelleyin.
class LegalDocuments {
  const LegalDocuments._();

  static const String termsOfService = r'''
LOVENME KULLANIM ŞARTLARI (HİZMET KOŞULLARI)

Yürürlük Tarihi: 21.09.2025
Son Güncelleme: 21.09.2025
Hizmet Sağlayıcı (Veri Sorumlusu): Burak Ohrili
Adres: Gazi Osman Paşa Mahallesi 5499/1 Sokak No:9 Kat:1 Bornova / İzmir
MERSİS / Ticaret Sicil No: TC 35509755908
Vergi Dairesi ve No: EGE VD 6360302767
lovenmeapp@gmail.com

Barındırma/Hizmet Altyapısı: Apple App Store, Google Play, Google Cloud/Firebase (Authentication, Firestore, Storage, Cloud Messaging, Analytics, Crashlytics, App Check), Google Maps ve Places API, Apple StoreKit ve Google Play Billing, Resend Mail, Google Workspace, NetGSM

Bu Kullanım Şartları ("Şartlar"), Lovenme mobil uygulaması ve ilgili web/servisleri (hep birlikte "Hizmet") kullanımınıza ilişkin yasal sözleşmeyi oluşturur. Hizmeti indirerek, hesap oluşturarak veya kullanarak bu Şartlar ile Gizlilik Politikası ve Çerez/İzleme Teknolojileri Politikasını kabul etmiş sayılırsınız. Şartları kabul etmiyorsanız Hizmeti kullanmayınız.

1. Tanımlar
Lovenme / Biz: Burak Ohrili.
Kullanıcı / Siz: 18 yaşını doldurmuş, Hizmeti kullanan gerçek kişi.
Hesap: Uygulamada oluşturduğunuz üyelik profili.
Premium: Ücretli abonelik paketi/leri.
Sanal Ürünler: Uygulama içinde satılan Elmas vb. dijital hak/öğe.
İçerik: Profil fotoğrafı, yazı, ses kaydı, video, mesajlar ve diğer kullanıcı paylaşımları.
Üçüncü Taraflar: Apple App Store, Google Play, Google Cloud/Firebase (Authentication, Firestore, Storage, Cloud Messaging, Analytics, Crashlytics, App Check), Google Maps ve Places API, Apple StoreKit ve Google Play Billing, Resend Mail, Google Workspace, NetGSM vb. hizmet sağlayıcılar.

2. Uygunluk ve Hesap
2.1. Yaş Sınırı: Hizmet yalnızca 18+ içindir. 18 yaş altı kullanım kesinlikle yasaktır.
2.2. Kayıt: Hesap; e-posta ve şifre ile oluşturulur; e-posta ve telefon doğrulaması istenir. Verdiğiniz tüm bilgilerin doğru, güncel ve size ait olduğunu beyan edersiniz.
2.3. Tek Hesap: Her kullanıcı sadece 1 (bir) hesap oluşturabilir; hesabınızı devredemez, kiralayamaz, satamazsınız.
2.4. Güvenlik: Giriş bilgilerinizi gizli tutmakla yükümlüsünüz. Hesabınızın yetkisiz kullanımından doğan sonuçlardan siz sorumlusunuz.
2.5. Kimlik/Doğrulama: Güvenlik amacıyla gerektiğinde ek doğrulama (ör. SMS doğrulama, fotoğraf/yüz doğrulama) talep edebiliriz; sağlamazsanız hesabınız askıya alınabilir.

3. Hizmetin Kapsamı ve Özellikler
3.1. Lovenme; mekân/check-in temelli keşif ve bağlantı mantığıyla kullanıcıları ortak mekanlarda buluşturan bir sosyal keşif uygulamasıdır.
3.2. Bazı özellikler ücretsiz; bazıları Premium abonelik veya Sanal Ürün satın alımı ile sunulur.
3.3. Konum: Çalışma, favori/ziyaret ettiğiniz check-in yaptığınız mekânlara göre öneriler üretilmesine dayanır. Uygulama, cihazınızın konum izinlerine dayalı yaklaşık/kesin konum verilerini yalnızca açık rızanızla işler.
3.4. Mesajlaşma: Karşılıklı bağlantı isteği kabul edildikten sonra iletişim kurulabilir. Mesaj ve ses notları, iletimi sağlamak ve güvenlik/şikâyet süreçleri için makul süreyle saklanabilir.

4. Davranış Kuralları (Topluluk İlkeleri)
4.1. Saygı ve Doğruluk: Profilinizde gerçek sizi yansıtan bir yüz fotoğrafı bulundurmalı; başkasını taklit etmemeli, sahte/AI üretimi aldatıcı görseller kullanmamalısınız.
4.2. Yasak İçerik ve Eylemler:
a) Hukuka aykırı, tehditkâr, hakaret/iftira, müstehcen, cinsel istismar içeren, nefret/ayrımcılık barındıran içerikler;
b) Şiddet, intihar/öz zarar teşviki;
c) Başkasının kişisel verisini/özel hayatını izinsiz ifşa;
d) Fikri mülkiyet ihlali (foto/video/müzik vs. izinsiz paylaşım);
e) Spam, dolandırıcılık, "catfishing", kimlik avı;
f) Seks işçiliği/escortluk, narkotik/illegal ürün/servis teşviki;
g) Otomatik araç/bot/scraper, tersine mühendislik, güvenlik zafiyeti istismarı;
h) Reklam/ticari tanıtım, platform dışına yönlendirme ve veri kazıma;
i) 18 yaş altı bireylerle herhangi bir cinsel içerik/temas veya reşit olmayanların cinselleştirilmesine yönelik her türlü paylaşım.

4.3. Raporlama/Engelleme: Uygunsuz davranış veya güvenlik endişenizde bildir ve/veya engelle araçlarını kullanın.
4.4. Offline Görüşmeler: Tanışmalarınız ve fiziksel buluşmalarınız tamamen kendi sorumluluğunuzdadır. İlk buluşmaları kamusal alanda yapmanızı, yakınınıza bilgi vermenizi öneririz.

5. Moderasyon, Askıya Alma ve Fesih
5.1. Şartlara aykırılık, güvenlik riski, sahte profil şüphesi, yargı mercilerinden gelen talepler veya uzun süreli inaktivite hâlinde hesabı uyarma/özellik kısıtlama/askıya alma veya feshetme hakkımız saklıdır.
5.2. Ağır ihlallerde derhal ve süresiz yasak uygulanabilir.
5.3. Sizin fesih hakkınız: Hesabınızı dilediğiniz an "Ayarlar > Hesabımı Sil" üzerinden kalıcı olarak silebilirsiniz.

6. Premium Abonelikler
6.1. Premium; sınırsız bağlantı isteği, tüm check-in geçmişine erişim, karşılaşma geçmişi ve seri koruması gibi avantajlar içerir. Bir mekanın topluluğunu görmek için o mekana check-in yapmış olmak gerekir; bu, Premium ile veya başka bir satın alma ile ATLANAMAZ.
6.2. Satın Alma ve Faturalama: Mobil abonelikler; Apple App Store / Google Play üzerinden, ilgili platformun kullanım/ödeme şartlarına tabi olarak tahsil edilir.
6.3. Otomatik Yenileme: Premium, aksi belirtilmedikçe otomatik yenilenir. İptal etmek için dönem bitiminden en az 24 saat önce App Store/Google Play üzerinden abonelik yenilemeyi kapatınız.

7. Sanal Ürünler: Elmas ve Öne Çıkan Mesaj Hakkı
7.1. Elmas ve öne çıkan mesaj hakkı gibi sanal ürünler yalnızca uygulama içi kullanım amaçlı, parasal karşılığı olmayan dijital değerlerdir.
7.2. Sanal ürün alımları kesindir, iade edilemez; nakde çevrilemez, devredilemez.

8. Fikri Mülkiyet
8.1. Lovenme ve logoları, tasarım, yazılım, veri tabanı dahil tüm unsurların mali/sınai hakları Burak Ohrili'ye aittir.
8.2. Kullanıcı İçerikleri: İçeriklerin sahibi sizsiniz; Hizmeti sağlamak/geliştirmek amacıyla dünya çapında, münhasır olmayan, bedelsiz kullanım lisansı sağlarsınız.

9. Sorumluluk Reddi ve Sınırlamalar
9.1. Hizmet "olduğu gibi" sunulur; kesintisiz, hatasız çalışacağına dair garanti verilmez.
9.2. Kullanıcı davranışlarından (çevrimiçi/çevrimdışı etkileşimler) doğacak zararlardan sorumluluk kabul edilmez.

10. Uyuşmazlık Çözümü
10.1. Öncelikle lovenmeapp@gmail.com üzerinden bize ulaşarak uyuşmazlıklara dostane çözüm arayınız.
10.2. Uygulanacak hukuk: Türkiye Cumhuriyeti Hukuku.

11. İletişim
Burak Ohrili
Adres: Gazi Osman Paşa Mahallesi 5499/1 Sokak No:9 Kat:1 Bornova / İzmir
E-posta: lovenmeapp@gmail.com
''';

  static const String privacyPolicy = r'''
LOVENME GİZLİLİK POLİTİKASI
Son Güncelleme Tarihi: 19.12.2025

Bu Gizlilik Politikası, Lovenme mobil uygulamasının ("Uygulama") kullanımı sırasında işlenen kişisel verilere ilişkin olarak kullanıcıları bilgilendirmek amacıyla hazırlanmıştır.

Lovenme, kişisel verilerinizi yürürlükteki mevzuata uygun olarak; başta 6698 sayılı Kişisel Verilerin Korunması Kanunu (KVKK) ve Avrupa Birliği Genel Veri Koruma Tüzüğü (GDPR) olmak üzere ilgili düzenlemelere uygun şekilde işler.

1. Veri Sorumlusu
Unvan: Burak Ohrili
Yetkili: Burak Ohrili
Adres: Gazi Osman Paşa Mah. 5499/1 Sokak No:9 D:2 Bornova / İzmir / Türkiye
E-posta: lovenmeapp@gmail.com

2. İşlenen Kişisel Veriler
Uygulama kapsamında aşağıdaki kişisel veriler işlenmektedir:

2.1. Kimlik ve İletişim Bilgileri
• Görünen ad (profil adı)
• E-posta adresi
• Telefon numarası

Bu veriler, kullanıcı hesabının oluşturulması, doğrulanması ve güvenliğinin sağlanması amacıyla işlenir.

2.2. Kullanıcı İçerikleri
• Profil fotoğrafları
• Mesajlaşma (DM) içerikleri
• Check-in paylaşımları ve açıklamaları

Mesaj içerikleri yalnızca hizmetin sunulması amacıyla saklanır ve üçüncü kişilerle paylaşılmaz.

2.3. Konum Bilgisi
• Kesin konum bilgisi (precise location)

Konum bilgisi yalnızca:
• Yakındaki mekânları göstermek,
• Check-in yapılmasını sağlamak,
• Son 24 saatlik check-in'leri görüntülemek

amaçlarıyla, kullanıcının açık izniyle işlenir.
Uygulama, arka planda sürekli konum takibi yapmaz.

2.4. Kullanım ve Teknik Veriler
• Kullanıcı kimliği (User ID)
• Uygulama içi etkileşimler (bağlantı isteği, mesajlaşma, check-in)
• Hata ve çökme kayıtları (varsa)

Bu veriler, uygulamanın güvenli ve düzgün çalışmasını sağlamak amacıyla kullanılır.

2.5. Satın Alma Bilgileri
• Abonelik ve satın alma durumu

Ödeme kartı veya banka bilgileri Lovenme tarafından toplanmaz veya saklanmaz. Tüm ödeme işlemleri ilgili uygulama mağazaları (Apple App Store vb.) üzerinden gerçekleştirilir.

3. Kişisel Verilerin Toplanma Yöntemi
Kişisel veriler;
• Kullanıcı tarafından doğrudan sağlanan bilgiler,
• Uygulama kullanımı sırasında otomatik olarak oluşan veriler,
• Kimlik doğrulama ve bildirim hizmetleri aracılığıyla
toplanmaktadır.

4. Kişisel Verilerin İşlenme Amaçları
Kişisel veriler aşağıdaki amaçlarla işlenmektedir:
• Kullanıcı hesabının oluşturulması ve yönetilmesi
• Mesajlaşma, mekan bağlantısı ve check-in hizmetlerinin sunulması
• Yakındaki mekânların ve kullanıcıların gösterilmesi
• Güvenlik, sahtecilik ve kötüye kullanımın önlenmesi
• Uygulamanın teknik olarak sorunsuz çalışmasının sağlanması
• Yasal yükümlülüklerin yerine getirilmesi

5. Üçüncü Taraf Hizmet Sağlayıcılar
Uygulama kapsamında aşağıdaki hizmet sağlayıcılardan yararlanılmaktadır:
• Google Firebase (Authentication, Firestore, Storage, Cloud Messaging, Analytics, Crashlytics, App Check)
• Google Maps SDK ve Google Places API (yakınındaki mekanların gösterilmesi)
• Apple StoreKit ve Google Play Billing (uygulama içi satın alma)
• Resend (doğrulama e-postaları)
• NETGSM Telekomünikasyon A.Ş. (SMS doğrulama hizmetleri)

Bu hizmet sağlayıcılar, kişisel verileri yalnızca ilgili hizmeti sunmak amacıyla ve gizlilik yükümlülükleri çerçevesinde işler.

6. Reklam, Pazarlama ve Takip
Lovenme uygulamasında:
• Üçüncü taraf reklam hizmetleri,
• Kişiselleştirilmiş reklam,
• Pazarlama veya yeniden hedefleme,
• Uygulamalar arası kullanıcı takibi
bulunmamaktadır.

Kişisel veriler, reklam veya pazarlama amacıyla kullanılmaz ve paylaşılmaz.

7. Kişisel Verilerin Saklama Süresi
Kişisel veriler:
• Kullanıcı hesabı aktif olduğu sürece,
• Hesap silme talebi sonrasında ise yasal yükümlülükler saklı kalmak kaydıyla
makul süre boyunca saklanır ve ardından silinir veya anonim hale getirilir.

8. Kullanıcı Hakları
KVKK ve GDPR kapsamında kullanıcılar:
• Kişisel verilerine erişme,
• Düzeltme talep etme,
• Silme veya yok edilmesini isteme,
• Veri işlemeye itiraz etme,
• Açık rızayı geri çekme
haklarına sahiptir.

Bu haklara ilişkin talepler lovenmeapp@gmail.com adresi üzerinden iletilebilir.

9. Hesap Silme
Kullanıcılar, uygulama içindeki ilgili ayarlar aracılığıyla:
• Hesaplarını geçici olarak dondurabilir,
• Hesaplarını kalıcı olarak silebilir.

Hesap silme işlemi sonrası kişisel veriler, yasal zorunluluklar dışında sistemlerden kaldırılır.

10. Çocukların Gizliliği
Lovenme, 18 yaşından küçük kullanıcılara yönelik değildir. Reşit olmayan kullanıcılara ait hesaplar tespit edilmesi halinde silinir.

11. Güvenlik
Lovenme, kişisel verilerin gizliliğini ve güvenliğini sağlamak amacıyla teknik ve idari güvenlik önlemleri uygular. Ancak internet üzerinden yapılan veri iletimlerinin %100 güvenli olduğu garanti edilemez.

12. Politika Değişiklikleri
Bu Gizlilik Politikası zaman zaman güncellenebilir. Önemli değişiklikler uygulama içinden veya uygun iletişim kanallarıyla kullanıcılara bildirilir.

13. İletişim
Gizlilik politikası ve kişisel verilerle ilgili her türlü soru ve talep için:
📧 lovenmeapp@gmail.com
''';
}
