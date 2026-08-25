# Lovenme - Venue-Based Local Community Platform

Lovenme is a venue-based social discovery and local community platform. The product starts from real-world places: users discover nearby venues, check in, follow venue activity, and participate in a daily Venue Mayor system.

## 🚀 Ana Özellikler

### Venue Discovery
- Map-first local discovery with nearby cafes, restaurants, gyms, event spaces, and city spots
- Venue detail pages with recent activity, community presence, and local context
- Favorite venues and check-in history for personal local discovery

### Check-In System
- Users check in to venues they actually visit
- Venue activity is built around real-world presence
- Check-in history powers better local recommendations and shared context

### Venue Mayor
- Each venue can have a daily visible community leader
- Users compete with Diamonds for venue-specific visibility
- Mayor status is a location-based social game, not a generic messaging mechanic

### Controlled Communication
- Users can send limited connection requests
- Communication is opt-in and includes reporting, blocking, rate limits, and safety controls
- Shared venue context is shown before conversation becomes the focus

### Premium and Monetization
- Premium unlocks richer local discovery tools, extended history, venue visibility, special badges, and priority support
- Diamonds power Venue Mayor bids and venue visibility mechanics
- Future business tools can support venue promotions, local campaigns, and venue analytics

## 🛠️ Teknoloji Yığını

### Frontend
- **Flutter 3.0+** - Cross-platform mobil uygulama
- **Dart** - Ana programlama dili
- **Riverpod** - State management
- **Google Maps Flutter** - Harita entegrasyonu

### Backend & Services
- **Firebase Auth** - Kullanıcı kimlik doğrulama
- **Cloud Firestore** - NoSQL veritabanı
- **Firebase Storage** - Fotoğraf ve medya depolama
- **Cloud Functions** - Sunucu tarafı işlemler
- **Firebase Analytics** - Kullanım analitikleri

### Ödeme & Entegrasyonlar
- **In-App Purchase** - Premium abonelik yönetimi
- **Google Sign-In** - Sosyal medya girişi
- **Places API** - Mekan arama ve detayları

## 📱 Platformlar

- ✅ **Android** (API 21+)
- ✅ **iOS** (iOS 12.0+)

## 🔧 Kurulum ve Çalıştırma

### Gereksinimler
```bash
Flutter SDK: >=3.0.0 <4.0.0
Dart SDK: >=3.0.0
Android Studio / VS Code
```

### Kurulum Adımları
```bash
# Projeyi klonla
git clone [repo-url]
cd lovenmeapp

# Bağımlılıkları yükle
flutter pub get

# iOS için ek kurulum
cd ios && pod install && cd ..

# Uygulamayı çalıştır
flutter run
```

### Firebase Yapılandırması
1. `android/app/google-services.json` dosyasını ekle
2. `ios/Runner/GoogleService-Info.plist` dosyasını ekle
3. Firebase console'dan gerekli API'ları aktifleştir

## 📊 Proje Yapısı

```
lib/
├── core/                    # Temel modeller ve yardımcılar
│   ├── models/             # Veri modelleri (User, Connection, Premium)
│   └── theme/              # UI tema ayarları
├── presentation/           # UI katmanı
│   ├── pages/             # Ana sayfalar
│   │   ├── auth/          # Giriş/kayıt sayfaları
│   │   ├── discover/      # Keşfet sayfası
│   │   ├── profile/       # Profil yönetimi
│   │   └── onboarding/    # 7 adımlık kurulum
│   └── widgets/           # Yeniden kullanılabilir bileşenler
├── services/              # API ve servis katmanı
└── utils/                 # Yardımcı fonksiyonlar
```

## 🔑 Ana Özellik Detayları

### Profil Kurulum Süreci
1. **Temel Bilgiler**: Ad, soyad, yaş, cinsiyet
2. **Fotoğraf Yükleme**: 1-6 arası profil fotoğrafı
3. **Hobiler**: Çoklu seçim ile ilgi alanları
4. **Favori Mekanlar**: Google Places API ile mekan seçimi
5. **Email Doğrulama**: Güvenlik için email onayı
6. **Telefon Doğrulama**: SMS ile telefon onayı
7. **Final İnceleme**: Profil özeti ve onay

### Local Context Engine
- **Coğrafi Yakınlık**: Yakındaki mekanları ve topluluk hareketliliğini öne çıkarır
- **Ortak Mekanlar**: Paylaşılan mekan deneyimlerini sosyal bağlam olarak kullanır
- **Check-in Geçmişi**: Gerçek dünya aktivitelerine göre keşfi zenginleştirir
- **Venue Community**: Mekan lideri, son aktiviteler ve topluluk yoğunluğunu gösterir

## 📈 Performans Optimizasyonları

- **Lazy Loading**: Sayfa bazında veri yükleme
- **Image Caching**: Cached Network Image kullanımı
- **State Management**: Riverpod ile optimize edilmiş state
- **API Rate Limiting**: Google Places API isteklerinde kontrol
- **Memory Management**: Otomatik bellek temizliği

## 🔒 Güvenlik Önlemleri

- **Firebase Security Rules**: Güvenli veri erişimi
- **Input Validation**: Tüm kullanıcı girdilerinde doğrulama
- **Secure Storage**: Hassas verilerin şifrelenmiş saklanması
- **SSL Pinning**: Güvenli API iletişimi

## 📞 İletişim & Destek

- **Email**: support@lovenme.app
- **KVKK**: kvkk@lovenme.app
- **Versiyon**: 1.0.0+15
- **Package**: com.lovenme.app


