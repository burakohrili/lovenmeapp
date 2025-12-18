# 💕 LoveNMe - Modern Dating App

**LoveNMe** mekân temelli eşleşme mantığına dayalı, yenilikçi bir sosyal tanışma uygulamasıdır. Kullanıcılar favori mekanlarını paylaşarak ortak ilgi alanlarına sahip kişilerle eşleşir ve gerçek dünyada tanışır.

## 🚀 Ana Özellikler

### 👤 Kullanıcı Profili
- **7 Adımlık Profil Kurulumu**: Kişisel bilgiler, fotoğraflar, hobiler, favori mekanlar
- **Akıllı Fotoğraf Sistemi**: Çoklu fotoğraf desteği ve otomatik sıkıştırma
- **Detaylı Tercih Yönetimi**: Yaş aralığı, cinsiyet tercihleri, özel filtreler

### 🗺️ Mekân Tabanlı Eşleşme
- **Google Maps Entegrasyonu**: Gerçek zamanlı mekan keşfi
- **Favori Mekanlar**: 3-5 mekan seçimi ile kişiselleştirilmiş deneyim
- **Check-in Sistemi**: Mekanlarda bulunma kayıtları
- **Proximity Matching**: Yakınlık temelli akıllı eşleşme algoritması

### 💬 Mesajlaşma & Eşleşme
- **Karşılıklı Beğeni Sistemi**: Like/Pass mekanizması
- **Super Like**: Premium özellik ile öne çıkma
- **Gerçek Zamanlı Mesajlaşma**: Firebase Cloud Messaging
- **Ses Mesajları**: Flutter Sound entegrasyonu

### 💎 Premium Özellikler
- **3 Abonelik Paketi**: Haftalık (₺99.99), Aylık (₺299.99), 3 Aylık (₺499.99)
- **Sınırsız Beğeni**: Free limitler kaldırılır
- **Super Like Paketleri**: 3-30 arası super like hakkı
- **Gelişmiş Filtreleme**: Detaylı arama seçenekleri
- **Reklamsız Deneyim**: Kesintisiz kullanım

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
- 🔄 **Web** (Geliştirme aşamasında)

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
cd mydateapp

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
│   ├── models/             # Veri modelleri (User, Match, Premium)
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

### Eşleşme Algoritması
- **Coğrafi Yakınlık**: 5-20km arası mesafe kontrolü
- **Ortak Mekanlar**: Favori mekan benzerliği
- **Yaş Uyumluluğu**: Tercih edilen yaş aralıkları
- **Cinsiyet Filtreleri**: Kullanıcı tercihlerine göre

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

## 📄 Lisans

Bu proje özel bir lisans altında geliştirilmiştir. Detaylar için iletişime geçiniz.

---

💫 **LoveNMe ile gerçek aşk bir dokunuş uzağında!**
