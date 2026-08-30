const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onCall, onRequest} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {getAuth} = require("firebase-admin/auth");
const {getStorage} = require("firebase-admin/storage");
const {Resend} = require("resend");
const {defineString, defineSecret} = require("firebase-functions/params");
const functions = require("firebase-functions");
const axios = require("axios");
const cors = require("cors")({origin: true});
const {GoogleAuth} = require("google-auth-library");
const crypto = require("crypto");

initializeApp();

// ============================================================
// ORTAK GÜVENLİK YARDIMCILARI (30.08.2026)
// ============================================================

/**
 * Çağıranın oturum açmış olmasını zorunlu kılar.
 * Bu e-posta fonksiyonları eskiden auth istemiyordu; yani herkes
 * noreply@lovenme.app adresinden istediği adrese posta göndertebiliyordu
 * (açık röle + alan adı itibarı riski).
 */
function requireAuth(request) {
  if (!request.auth || !request.auth.uid) {
    throw new functions.https.HttpsError(
        "unauthenticated", "Bu işlem için giriş yapmalısınız.");
  }
  return request.auth.uid;
}

/** Yalnızca admin talebi olan kullanıcılar. */
function requireAdmin(request) {
  requireAuth(request);
  if (!request.auth.token || request.auth.token.admin !== true) {
    throw new functions.https.HttpsError(
        "permission-denied", "Bu işlem için yetkiniz yok.");
  }
  return request.auth.uid;
}

/**
 * Çağıranın gönderdiği metni HTML gövdesine gömmeden önce kaçırır.
 * `userName` daha önce doğrudan şablona giriyordu; giden postalara istediğini
 * enjekte etmek mümkündü.
 */
/**
 * Dokumanlari 500'luk parcalar halinde siler.
 * WriteBatch 500 islemle sinirlidir; bu fonksiyondaki bircok batch limitsizdi
 * ve yogun bir mekan/gun tum calistirmayi iptal ettirebiliyordu.
 */
async function deleteDocsInChunks(db, docs) {
  let removed = 0;
  for (let i = 0; i < docs.length; i += 450) {
    const slice = docs.slice(i, i + 450);
    const batch = db.batch();
    slice.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    removed += slice.length;
  }
  return removed;
}

function escapeHtml(value) {
  return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
}


// Parametreleri tanımla
const resendKey = defineString("RESEND_KEY");
const googleServiceAccountKey = defineSecret("GOOGLE_SERVICE_ACCOUNT_KEY");
const netgsmUsercode = defineString("NETGSM_USERCODE");
const netgsmPassword = defineString("NETGSM_PASSWORD");
const netgsmHeader = defineString("NETGSM_HEADER");
// NOT: RTDN audience icin ayri bir yapilandirma parametresi TUTMUYORUZ;
// fonksiyonun kendi URL'i audience olarak hesaplaniyor. Pub/Sub push
// aboneligi olustururken audience alani bos birakilirsa Google zaten push
// endpoint URL'ini kullanir.

// Push notification request handler - yeni sistem
exports.handleNotificationRequest = onDocumentCreated(
  "notification_requests/{requestId}",
  async (event) => {
    const request = event.data.data();
    const requestId = event.params.requestId;
    
    try {
      console.log("📤 Bildirim isteği işleniyor:", requestId);
      console.log("📋 Request data:", JSON.stringify(request, null, 2));
      
      // FCM Token kontrolü
      if (!request.fcmToken) {
        throw new Error("FCM token bulunamadı");
      }
      
      // Validate required fields
      if (!request.targetUserId) {
        throw new Error("Target user ID bulunamadı");
      }
      
      // Kullanıcının bildirim ayarlarını kontrol et
      const userDoc = await getFirestore()
        .collection("users")
        .doc(request.targetUserId)
        .get();
      
      if (!userDoc.exists) {
        throw new Error("Kullanıcı bulunamadı");
      }
      
      const userData = userDoc.data();
      const notificationSettings = {
        notifications: userData.notifications !== false, // Varsayılan true
        matchNotifications: userData.matchNotifications !== false, // Varsayılan true
        messageNotifications: userData.messageNotifications !== false, // Varsayılan true
      };
      
      console.log("📋 Kullanıcı bildirim ayarları:", notificationSettings);
      
      // Genel bildirimler kapalıysa hiç bildirim gönderme
      if (!notificationSettings.notifications) {
        console.log("🔕 Kullanıcı tüm bildirimleri kapattı, bildirim gönderilmiyor");
        await getFirestore()
          .collection("notification_requests")
          .doc(requestId)
          .update({
            processed: true,
            processedAt: new Date(),
            skipped: true,
            skipReason: "Kullanıcı bildirimleri kapattı",
          });
        return null;
      }
      
      // Bildirim tipine göre kontrol et
      const notificationType = (request.data && request.data.type) || "general";
      
      if (notificationType === "match" && !notificationSettings.matchNotifications) {
        console.log("🔕 Kullanıcı eşleşme bildirimlerini kapattı, bildirim gönderilmiyor");
        await getFirestore()
          .collection("notification_requests")
          .doc(requestId)
          .update({
            processed: true,
            processedAt: new Date(),
            skipped: true,
            skipReason: "Kullanıcı eşleşme bildirimlerini kapattı",
          });
        return null;
      }
      
      if (notificationType === "message" && !notificationSettings.messageNotifications) {
        console.log("🔕 Kullanıcı mesaj bildirimlerini kapattı, bildirim gönderilmiyor");
        await getFirestore()
          .collection("notification_requests")
          .doc(requestId)
          .update({
            processed: true,
            processedAt: new Date(),
            skipped: true,
            skipReason: "Kullanıcı mesaj bildirimlerini kapattı",
          });
        return null;
      }
      
      console.log("✅ Bildirim ayarları uygun, bildirim gönderiliyor...");
      
      const message = {
        notification: {
          title: request.title || "LoveNMe",
          body: request.body || "Yeni bildirim",
        },
        data: {
          type: request.data.type || "general",
          senderId: request.data.senderId || "",
          senderName: request.data.senderName || "",
          showSenderName: request.data.showSenderName || "false",
          venueId: request.data.venueId || "",
          venueName: request.data.venueName || "",
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          notification: {
            icon: "ic_notification",
            color: "#FF6B35",
            channel_id: "lovenme_channel",
            priority: "high",
            default_sound: true,
            default_vibrate_timings: true,
            notification_count: 1,
          },
          data: request.data || {},
        },
        apns: {
          payload: {
            aps: {
              alert: {
                title: request.title || "LoveNMe",
                body: request.body || "Yeni bildirim",
              },
              badge: 1,
              sound: "default",
              "content-available": 1,
              "mutable-content": 1,
            },
          },
          fcm_options: {
            image: request.imageUrl || null,
          },
        },
        token: request.fcmToken,
      };
      
      const response = await getMessaging().send(message);
      console.log("✅ Push notification gönderildi:", response);
      console.log("📊 Message structure:", JSON.stringify(message, null, 2));
      
      // İsteği işlendi olarak işaretle
      await getFirestore()
        .collection("notification_requests")
        .doc(requestId)
        .update({
          processed: true,
          processedAt: new Date(),
          messageId: response,
        });
      
      console.log("✅ Push notification başarıyla gönderildi ve işlendi");
      
      return null;
    } catch (error) {
      console.error("❌ Bildirim gönderme hatası:", error);
      
      // Hata durumunu kaydet
      await getFirestore()
        .collection("notification_requests")
        .doc(requestId)
        .update({
          processed: true,
          processedAt: new Date(),
          error: error.message,
        });
      
      return null;
    }
  }
);

// Email doğrulama fonksiyonu - GÜNCELLENMİŞ
exports.sendVerificationEmail = onCall(
  {
    region: "us-central1",
    cors: true,
    enforceAppCheck: false, // App Check bypass - email doğrulama için güvenli
  },
  async (request) => {
    requireAuth(request); // açık e-posta rölesi olmasın
    const {email, code} = request.data;
    const userName = escapeHtml(request.data.userName);
    
    console.log("📧 Dogrulama e-postasi gonderiliyor");
    
    // Input validation
    if (!email || !code || !userName) {
      console.error("Eksik parametreler");
      return {success: false, error: "Email, kod ve kullanıcı adı gerekli"};
    }
    
    // Email format validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      console.error("Geçersiz email formatı:", email);
      return {success: false, error: "Geçersiz email formatı"};
    }
    
    // Resend client'ı fonksiyon içinde oluştur
    const resend = new Resend(resendKey.value());
    
    try {
      const {data, error} = await resend.emails.send({
        from: "noreply@lovenme.app", 
        to: email,
        subject: "🔐 LoveNMe - Email Doğrulama Kodu",
        html: `
          <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 40px; text-align: center; border-radius: 10px 10px 0 0;">
              <h1 style="color: white; margin: 0; font-size: 28px;">LoveNMe</h1>
              <p style="color: rgba(255,255,255,0.9); margin-top: 10px;">Aşkın Dijital Hali</p>
            </div>
            <div style="background: white; padding: 40px; border: 1px solid #e0e0e0; border-radius: 0 0 10px 10px;">
              <h2 style="color: #333; margin-top: 0;">Merhaba ${userName}!</h2>
              <p style="color: #666; font-size: 16px;">Email adresinizi doğrulamak için aşağıdaki kodu kullanın:</p>
              <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 25px; text-align: center; margin: 30px 0; border-radius: 8px;">
                <span style="font-size: 42px; font-weight: bold; color: white; letter-spacing: 8px; font-family: monospace;">
                  ${code}
                </span>
              </div>
              <p style="color: #999; font-size: 14px; margin-top: 30px;">
                ⏱️ Bu kod 10 dakika geçerlidir.<br>
                🔒 Bu kodu kimseyle paylaşmayın.
              </p>
              <hr style="border: none; border-top: 1px solid #e0e0e0; margin: 30px 0;">
              <p style="color: #999; font-size: 12px;">
                Bu emaili siz talep etmediyseniz, lütfen dikkate almayın.
              </p>
            </div>
            <div style="text-align: center; padding: 20px; color: #999; font-size: 12px;">
              © 2026 LoveNMe. Tüm hakları saklıdır.<br>
              <a href="https://lovenme.app" style="color: #667eea; text-decoration: none;">lovenme.app</a>
            </div>
          </div>
        `,
      });
      
      if (error) {
        console.error("Resend hatası:", error);
        return {success: false, error: error.message};
      }
      
      console.log(`✅ Email gönderildi: ${data.id}`);
      return {success: true, emailId: data.id};
      
    } catch (error) {
      console.error("Email hatası:", error);
      return {success: false, error: error.message};
    }
  }
);

// Daily reset function - Her gece 00:00'da çalışır - UPDATED FOR PREMIUM QUEUE
exports.dailyReset = onSchedule(
  {
    schedule: "0 0 * * *",
    timeZone: "Europe/Istanbul",
    region: "us-central1",
  },
  async () => {
    const db = getFirestore();
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    
    console.log("🌙 Daily reset başlatıldı:", now.toISOString());
    
    try {
      let totalProcessed = 0;
      let errors = 0;
      
      // 1. GÜNLÜK LİMİTLERİ RESET ET
      // ============================================================
      // 1. KULLANICI GÜNLÜK LİMİTLERİ
      // ============================================================
      // ESKİ HATALAR (30.08.2026'da düzeltildi):
      //  a) `batch` döngü dışında bir kez oluşturuluyor, 500'de commit edilip
      //     YENİDEN OLUŞTURULMUYORDU → 501. kullanıcıda
      //     "Cannot modify a WriteBatch that has been committed" ile çöküyordu.
      //  b) `.where("isActive","==",true)` filtresi vardı; ama onboarding'in
      //     son adımı kullanıcı dokümanını merge:false ile yazıp `isActive`
      //     alanını siliyordu → onboarding'i tamamlamış HİÇBİR kullanıcı
      //     eşleşmiyordu, yani bu iş yıllardır boşa çalışıyordu.
      //  c) Sayfalama yoktu; tüm kullanıcılar tek seferde belleğe alınıyordu.
      console.log("Kullanici limitleri resetleniyor...");

      const PAGE = 500;
      let lastUserDoc = null;
      let usersProcessed = 0;

      // eslint-disable-next-line no-constant-condition
      while (true) {
        let q = db.collection("users").orderBy("__name__").limit(PAGE);
        if (lastUserDoc) q = q.startAfter(lastUserDoc);

        const page = await q.get();
        if (page.empty) break;

        const batch = db.batch(); // her sayfa için YENİ batch
        for (const userDoc of page.docs) {
          const userData = userDoc.data();
          const isPremium = userData.isPremium || false;

          const common = {
            // Hem sunucu hem istemci aynı işareti okusun diye ikisi de yazılır.
            // (İstemci `lastLimitReset`, sunucu `lastDailyReset` kullanıyordu;
            //  bu yüzden istemci her sabah tekrar reset ediyordu.)
            lastDailyReset: now,
            lastLimitReset: now,
          };

          if (isPremium && userData.premiumUntil) {
            const premiumUntil = userData.premiumUntil.toDate();
            if (now > premiumUntil) {
              batch.update(userDoc.ref, Object.assign({
                isPremium: false,
                premiumUntil: null,
                premiumType: null,
                dailyChatRequestsRemaining: 5,
              }, common));
            } else {
              batch.update(userDoc.ref, Object.assign({
                dailyChatRequestsRemaining: 999,
              }, common));
            }
          } else {
            batch.update(userDoc.ref, Object.assign({
              dailyChatRequestsRemaining: 5,
            }, common));
          }

          usersProcessed++;
        }

        await batch.commit();
        lastUserDoc = page.docs[page.docs.length - 1];
        if (page.size < PAGE) break;
      }

      totalProcessed = usersProcessed;
      console.log(`${usersProcessed} kullanici limiti resetlendi`);

      // ============================================================
      // 2. DÜNKÜ MUHTARLAR
      // ============================================================
      const mayorSnapshot = await db.collection("daily_mayors")
        .where("date", "<", today)
        .limit(2000)
        .get();
      const mayorsCleared = await deleteDocsInChunks(db, mayorSnapshot.docs);
      console.log(`${mayorsCleared} eski muhtar kaydi temizlendi`);

      // ============================================================
      // 3. 3 GÜNDEN ESKİ CHECK-IN'LER
      // ============================================================
      const threeDaysAgo = new Date(today.getTime() - 3 * 24 * 60 * 60 * 1000);
      const oldCheckInsSnapshot = await db.collection("check_ins")
        .where("checkInTime", "<", threeDaysAgo)
        .limit(2000)
        .get();
      const checkInsCleared =
        await deleteDocsInChunks(db, oldCheckInsSnapshot.docs);
      console.log(`${checkInsCleared} eski check-in silindi`);

      // ============================================================
      // 4. SÜRESİ DOLMUŞ CHECK-IN HISTORY
      // ============================================================
      const oldHistorySnapshot = await db.collection("check_in_history")
        .where("expiresAt", "<=", now)
        .limit(2000)
        .get();
      const historyCleared =
        await deleteDocsInChunks(db, oldHistorySnapshot.docs);
      console.log(`${historyCleared} eski check-in history silindi`);

      // ============================================================
      // 5. GEÇİCİ FAVORİ HISTORY
      // ============================================================
      // ESKİ HATA: `.where("isPermanent","!=",true)` ile
      // `.where("registrationDate","<",...)` aynı sorguda kullanılıyordu.
      // Firestore iki FARKLI alanda eşitsizliğe izin vermez; sorgu her
      // çalıştırmada fırlıyor, catch'e düşüyor ve fonksiyonun 6., 7., 8.
      // adımları (bildirim temizliği, log, premium kuyruğu) HİÇ çalışmıyordu.
      // Çözüm: tek eşitsizlikle sorgula, kalıcı olanları kodda ele.
      const thirtyDaysAgo = new Date(today.getTime() - 30 * 24 * 60 * 60 * 1000);
      const tempFavoriteSnapshot = await db.collection("favorite_venue_history")
        .where("registrationDate", "<", thirtyDaysAgo)
        .limit(2000)
        .get();
      const deletableFavorites = tempFavoriteSnapshot.docs
        .filter((d) => d.data().isPermanent !== true);
      const favoritesCleared =
        await deleteDocsInChunks(db, deletableFavorites);
      console.log(`${favoritesCleared} gecici favori history silindi`);

      // ============================================================
      // 6. ESKİ BİLDİRİMLER
      // ============================================================
      const sevenDaysAgo = new Date(today.getTime() - 7 * 24 * 60 * 60 * 1000);
      const oldNotificationsSnapshot = await db.collection("notifications")
        .where("createdAt", "<", sevenDaysAgo)
        .limit(2000)
        .get();
      const notificationsCleared =
        await deleteDocsInChunks(db, oldNotificationsSnapshot.docs);
      console.log(`${notificationsCleared} eski bildirim silindi`);

      // ============================================================
      // 7. PREMIUM KUYRUĞU
      // ============================================================
      await activateQueuedPremiums(db, now);

      // ============================================================
      // 8. LOG (tek kez — eskiden aynı kayıt iki kez yazılıyordu)
      // ============================================================
      await db.collection("system_logs").add({
        type: "daily_reset",
        timestamp: now,
        usersProcessed: totalProcessed,
        mayorsCleared: mayorsCleared,
        checkInsCleared: checkInsCleared,
        historyCleared: historyCleared,
        favoritesCleared: favoritesCleared,
        notificationsCleared: notificationsCleared,
        errors: errors,
        success: true,
      });

      console.log("Gunluk reset tamamlandi.");

      return {success: true, processed: totalProcessed};
      
    } catch (error) {
      console.error("❌ Daily reset error:", error);
      
      // Hata log'u kaydet
      await db.collection("system_logs").add({
        type: "daily_reset",
        timestamp: now,
        error: error.message,
        success: false,
      });
      
      throw error;
    }
  }
);

// 🕒 PREMIUM STATUS CHECKER - Her saat başı premium süre dolumu kontrol eder
exports.checkPremiumStatus = onSchedule({
  schedule: "0 * * * *", // Her saat başı
  timeZone: "Europe/Istanbul",
  region: "us-central1",
}, async () => {
  console.log("💎 Premium status kontrol ediliyor...");
  
  try {
    const db = getFirestore();
    const now = new Date();
    
    // Süresi dolmuş premium abonelikleri bul
    const expiredPremiumsSnapshot = await db.collection("users")
      .where("isPremium", "==", true)
      .where("premiumUntil", "<=", now)
      .limit(100)
      .get();
    
    if (expiredPremiumsSnapshot.empty) {
      console.log("💎 Süresi dolmuş premium abonelik bulunamadı");
      return { success: true, expiredCount: 0 };
    }
    
    const batch = db.batch();
    let expiredCount = 0;
    
    for (const userDoc of expiredPremiumsSnapshot.docs) {
      const updates = {
        isPremium: false,
        premiumUntil: null,
        premiumType: null,
        dailyChatRequestsRemaining: 5, // 💬 Normal: 5 chat/gün
        rewindsRemaining: 0,
        // superChatsRemaining: unchanged - IAP paketler korunur! 🔥
        premiumExpiredAt: now,
      };
      
      batch.update(userDoc.ref, updates);
      expiredCount++;
      
      console.log(`💎 Premium süresi doldu: ${userDoc.id}`);
    }
    
    await batch.commit();
    
    // Premium süresi dolanlara kuyruktan yeni premium aktif et
    if (expiredCount > 0) {
      console.log("🎫 Süresi dolan premium'lar için kuyruk kontrolü yapılıyor...");
      await activateQueuedPremiums(db, now);
    }
    
    // Log oluştur
    await db.collection("system_logs").add({
      type: "premium_expiry_check",
      timestamp: now,
      expiredCount: expiredCount,
      status: "completed"
    });
    
    console.log(`💎 ${expiredCount} premium aboneliği sonlandırıldı`);
    return { success: true, expiredCount };
    
  } catch (error) {
    console.error("❌ Premium status kontrol hatası:", error);
    
    await getFirestore().collection("system_logs").add({
      type: "premium_check_error",
      timestamp: new Date(),
      error: error.message,
      status: "failed"
    });
    
    throw error;
  }
});

// 🧹 CLEANUP OLD DATA - Her gün sabah 02:00'da eski verileri temizler
exports.cleanupOldData = onSchedule({
  schedule: "0 2 * * *", // Her gün sabah 02:00
  timeZone: "Europe/Istanbul", 
  region: "us-central1",
}, async () => {
  console.log("🧹 Eski veriler temizleniyor...");
  
  try {
    const db = getFirestore();
    const now = new Date();
    const oneWeekAgo = new Date(now.getTime() - (7 * 24 * 60 * 60 * 1000));
    const oneMonthAgo = new Date(now.getTime() - (30 * 24 * 60 * 60 * 1000));
    
    let totalDeleted = 0;
    
    // 1. Eski notifications temizle (1 hafta)
    const oldNotificationsSnapshot = await db.collection("notifications")
      .where("createdAt", "<", oneWeekAgo)
      .limit(2000)
      .get();
    // Eskiden seri `await doc.ref.delete()` dongusuydu: 1000 kayit =
    // 1000 ardisik gidis-donus, 540 sn zaman asimina takiliyordu.
    totalDeleted += await deleteDocsInChunks(db, oldNotificationsSnapshot.docs);
    console.log(`🔔 ${oldNotificationsSnapshot.size} eski bildirim temizlendi`);
    
    // 2. Eski notification_requests temizle (1 hafta)
    const oldRequestsSnapshot = await db.collection("notification_requests")
      .where("createdAt", "<", oneWeekAgo)
      .limit(2000)
      .get();
    // Eskiden seri `await doc.ref.delete()` dongusuydu: 1000 kayit =
    // 1000 ardisik gidis-donus, 540 sn zaman asimina takiliyordu.
    totalDeleted += await deleteDocsInChunks(db, oldRequestsSnapshot.docs);
    console.log(`📤 ${oldRequestsSnapshot.size} eski bildirim isteği temizlendi`);
    
    // 3. Eski system_logs temizle (1 ay)
    const oldLogsSnapshot = await db.collection("system_logs")
      .where("timestamp", "<", oneMonthAgo)
      .limit(2000)
      .get();
    // Eskiden seri `await doc.ref.delete()` dongusuydu: 1000 kayit =
    // 1000 ardisik gidis-donus, 540 sn zaman asimina takiliyordu.
    totalDeleted += await deleteDocsInChunks(db, oldLogsSnapshot.docs);
    console.log(`📋 ${oldLogsSnapshot.size} eski sistem logu temizlendi`);
    
    // Cleanup log oluştur
    await db.collection("system_logs").add({
      type: "data_cleanup",
      timestamp: now,
      totalDeleted: totalDeleted,
      status: "completed"
    });
    
    console.log(`🧹 Cleanup tamamlandı: ${totalDeleted} kayıt silindi`);
    return { success: true, totalDeleted };
    
  } catch (error) {
    console.error("❌ Cleanup hatası:", error);
    
    await getFirestore().collection("system_logs").add({
      type: "cleanup_error",
      timestamp: new Date(),
      error: error.message,
      status: "failed"
    });
    
    throw error;
  }
});

// 📊 SYSTEM STATUS CHECKER - Manuel olarak sistem durumunu kontrol eder
exports.getSystemStatus = onCall({
  region: "us-central1",
  enforceAppCheck: false, // Public endpoint - App Check bypass
}, async (request) => {
  // Eskiden auth'suz herkese açıktı: kullanıcı ve premium sayıları sızıyordu.
  requireAdmin(request);
  console.log("📊 Sistem durumu kontrol ediliyor...");
  
  try {
    const db = getFirestore();
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    
    // 1. Son reset logunu kontrol et
    const recentResetLog = await db.collection("system_logs")
      .where("type", "==", "daily_reset")
      .orderBy("timestamp", "desc")
      .limit(1)
      .get();
    
    // 2. Sample user data
    const usersSnapshot = await db.collection("users")
      .limit(50)
      .get();
    
    let premiumUsers = 0;
    let normalUsers = 0;
    let needsReset = 0;
    
    usersSnapshot.forEach(doc => {
      const data = doc.data();
      if (data.isPremium) premiumUsers++;
      else normalUsers++;
      
      const lastReset = data.lastLimitReset ? data.lastLimitReset.toDate() : null;
      if (!lastReset || lastReset < today) needsReset++;
    });
    
    // 3. Daily mayors count
    const todayMayorsSnapshot = await db.collection("daily_mayors")
      .where("date", ">=", today)
      .get();
    
    const systemStatus = {
      timestamp: now,
      lastDailyReset: !recentResetLog.empty ? {
        time: recentResetLog.docs[0].data().timestamp.toDate(),
        status: recentResetLog.docs[0].data().status
      } : null,
      userStats: {
        sampleSize: usersSnapshot.size,
        premiumUsers,
        normalUsers,
        needsReset
      },
      dailyMayors: {
        todayCount: todayMayorsSnapshot.size
      },
      cloudFunctions: {
        dailyReset: "Scheduled at 00:00 Turkey Time",
        premiumChecker: "Scheduled every hour",
        cleanup: "Scheduled at 02:00 Turkey Time",
        venueCleanup: "Scheduled every hour"
      }
    };
    
    console.log("📊 Sistem durumu:", systemStatus);
    return { success: true, systemStatus };
    
  } catch (error) {
    console.error("❌ Sistem durumu kontrol hatası:", error);
    return { success: false, error: error.message };
  }
});

// Venue kapanış saatlerine göre check-in temizleme - Her saat başı çalışır
exports.cleanupVenueCheckIns = onSchedule(
  {
    schedule: "0 * * * *", // Her saat başı
    timeZone: "Europe/Istanbul",
    region: "us-central1",
  },
  async () => {
    const db = getFirestore();
    const now = new Date();
    
    console.log("🧹 Venue check-in cleanup başlatıldı:", now.toISOString());
    console.log(`🕐 Şu anki saat: ${now.getHours()}:${now.getMinutes().toString().padStart(2, '0')}`);
    
    try {
      // ============================================================
      // ESKİ TASARIM SORUNU (30.08.2026'da değiştirildi):
      // Bu iş saatte bir `venues` koleksiyonunun TAMAMINI filtresiz ve
      // limitsiz okuyordu. 50k mekanda günde ~1.2M okuma demekti ve mekan
      // sayısı büyüdükçe doğrusal olarak pahalılaşıyordu. Üstelik history ve
      // silme batch'leri 500'lük parçalara bölünmediği için yoğun bir mekan
      // (günde 500+ check-in) tüm saatlik çalıştırmayı iptal ettiriyordu.
      //
      // YENİ TASARIM: Sorguyu tersine çevir. Mekanlardan değil, BUGÜNKÜ
      // CHECK-IN'LERDEN başla — bunlar her zaman çok daha az. Yalnızca bugün
      // check-in almış mekanların dokümanı okunur.
      // ============================================================
      let totalCleaned = 0;
      let venuesProcessed = 0;

      const todayStart = new Date(
        now.getFullYear(), now.getMonth(), now.getDate());
      const todayEnd = new Date(
        now.getFullYear(), now.getMonth(), now.getDate() + 1);

      // 1) Bugünkü check-in'leri sayfalayarak topla, mekana göre grupla.
      const byVenue = new Map();
      let cursor = null;
      // eslint-disable-next-line no-constant-condition
      while (true) {
        let q = db.collection("check_ins")
          .where("checkInTime", ">=", todayStart)
          .where("checkInTime", "<", todayEnd)
          .orderBy("checkInTime")
          .limit(1000);
        if (cursor) q = q.startAfter(cursor);

        const page = await q.get();
        if (page.empty) break;

        for (const doc of page.docs) {
          const venueId = doc.data().venueId;
          if (!venueId) continue;
          if (!byVenue.has(venueId)) byVenue.set(venueId, []);
          byVenue.get(venueId).push(doc);
        }

        cursor = page.docs[page.docs.length - 1];
        if (page.size < 1000) break;
      }

      console.log(`Bugun check-in alan mekan sayisi: ${byVenue.size}`);

      // 2) Yalnızca bu mekanların dokümanlarını oku (10'luk gruplar).
      const venueIds = Array.from(byVenue.keys());
      for (let i = 0; i < venueIds.length; i += 10) {
        const chunk = venueIds.slice(i, i + 10);
        const refs = chunk.map((id) => db.collection("venues").doc(id));
        const venueDocs = await db.getAll(...refs);

        for (const venueDoc of venueDocs) {
          venuesProcessed++;
          const venueId = venueDoc.id;
          const venueData = venueDoc.exists ? venueDoc.data() : {};
          const venueName = venueData.name || "Bilinmeyen Mekan";

          // Kapanış saatini belirle (mekan yoksa varsayılan 02:00).
          let closingHour = 2;
          let closingMinute = 0;
          if (venueData.closingTime) {
            const parts = String(venueData.closingTime).split(":");
            closingHour = parseInt(parts[0]) || 2;
            closingMinute = parts.length > 1 ? (parseInt(parts[1]) || 0) : 0;
          }

          let closingDateTime;
          if (closingHour < 6) {
            // Gece yarısından sonra kapanan mekanlar ertesi güne sarkar.
            const tomorrow = new Date(now);
            tomorrow.setDate(tomorrow.getDate() + 1);
            closingDateTime = new Date(tomorrow.getFullYear(),
              tomorrow.getMonth(), tomorrow.getDate(),
              closingHour, closingMinute);
          } else {
            closingDateTime = new Date(now.getFullYear(), now.getMonth(),
              now.getDate(), closingHour, closingMinute);
          }

          if (now < closingDateTime) continue; // henüz açık

          const docs = byVenue.get(venueId) || [];
          if (docs.length === 0) continue;

          // 3) Önce history'e taşı, sonra sil — ikisi de 450'lik parçalarda.
          for (let j = 0; j < docs.length; j += 450) {
            const slice = docs.slice(j, j + 450);
            const historyBatch = db.batch();
            for (const checkInDoc of slice) {
              const historyDoc = db.collection("check_in_history").doc();
              historyBatch.set(historyDoc, Object.assign({},
                checkInDoc.data(), {
                  originalCheckInId: checkInDoc.id,
                  movedToHistoryAt: now,
                  expiresAt: new Date(
                    now.getTime() + 30 * 24 * 60 * 60 * 1000),
                  forDiscoverMatching: true,
                }));
            }
            await historyBatch.commit();
          }

          const cleaned = await deleteDocsInChunks(db, docs);
          totalCleaned += cleaned;
          console.log(`${venueName}: ${cleaned} check-in history'e tasindi`);

          // 4) Günlük muhtarı temizle.
          // Deterministik kimlikli doküman + auto-ID ile yazılmış olanlar.
          // (checkin_service iki farklı biçimde yazıyor; eskiden yalnızca
          //  deterministik olan siliniyor, auto-ID olanlar sonsuza dek
          //  birikiyordu.)
          const todayKey = `${now.getFullYear()}-` +
            `${(now.getMonth() + 1).toString().padStart(2, "0")}-` +
            `${now.getDate().toString().padStart(2, "0")}`;
          try {
            await db.collection("daily_mayors")
              .doc(`${venueId}_${todayKey}`).delete();
          } catch (e) {
            console.error("daily_mayors silinemedi:", e.message);
          }
          try {
            const strays = await db.collection("daily_mayors")
              .where("venueId", "==", venueId)
              .where("date", "<", todayEnd)
              .limit(200)
              .get();
            await deleteDocsInChunks(db, strays.docs);
          } catch (e) {
            console.error("auto-ID muhtar temizligi:", e.message);
          }
        }
      }

      // Log kaydet
      await db.collection("system_logs").add({
        type: "venue_checkin_cleanup",
        timestamp: now,
        venuesProcessed: venuesProcessed,
        checkInsCleared: totalCleaned,
        currentHour: now.getHours(),
        success: true,
      });
      
      if (totalCleaned > 0) {
        console.log(`✅ Venue cleanup tamamlandı:`);
        console.log(`   🏢 ${venuesProcessed} venue kontrol edildi`);
        console.log(`   🧹 ${totalCleaned} check-in temizlendi`);
      } else {
        console.log(`ℹ️ Temizlenecek check-in bulunamadı (${venuesProcessed} venue kontrol edildi)`);
      }
      
      return {success: true, cleaned: totalCleaned, processed: venuesProcessed};
      
    } catch (error) {
      console.error("❌ Venue cleanup error:", error);
      
      // Hata log'u kaydet
      await db.collection("system_logs").add({
        type: "venue_checkin_cleanup",
        timestamp: now,
        error: error.message,
        success: false,
      });
      
      throw error;
    }
  }
);

// Manuel test fonksiyonu - Sadece development için
exports.testDailyReset = onCall(
  {
    region: "us-central1",
  },
  async (request) => {
    if (!request.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Authentication required");
    }
    
    console.log("🧪 Manuel daily reset test başlatıldı");
    
    try {
      // Daily reset fonksiyonunu çağır (simulated)
      const db = getFirestore();
      const now = new Date();
      
      await db.collection("system_logs").add({
        type: "manual_daily_reset_test",
        timestamp: now,
        triggeredBy: request.auth.uid,
        success: true,
      });
      
      return {success: true, message: "Test reset logged"};
    } catch (error) {
      console.error("❌ Test daily reset error:", error);
      throw new functions.https.HttpsError("internal", error.message);
    }
  }
);

// 🎫 PREMIUM KUYRUK YÖNETİMİ - Kuyruktaki premium abonelikleri aktif eder
async function activateQueuedPremiums(db, now) {
  try {
    console.log("🔍 Aktif edilecek kuyruklu premium abonelikler aranıyor...");
    
    // Bugün başlaması gereken kuyruktaki premium abonelikleri bul
    const queuedPremiumsSnapshot = await db.collection("premium_subscriptions")
      .where("isQueued", "==", true)
      .where("startDate", "<=", now)
      .limit(100)
      .get();
    
    if (queuedPremiumsSnapshot.empty) {
      console.log("📋 Aktif edilecek kuyruklu premium abonelik bulunamadı");
      return { success: true, activatedCount: 0 };
    }
    
    const batch = db.batch();
    let activatedCount = 0;
    
    for (const subscriptionDoc of queuedPremiumsSnapshot.docs) {
      const subscriptionData = subscriptionDoc.data();
      const userId = subscriptionData.userId;
      const premiumType = subscriptionData.type;
      const endDate = subscriptionData.endDate.toDate();
      
      console.log(`🎫 Premium kuyruktan aktif ediliyor: ${userId} - ${premiumType} (${endDate})`);
      
      // Premium aboneliği aktif et
      batch.update(subscriptionDoc.ref, {
        isQueued: false,
        isActive: true,
        activatedAt: now,
      });
      
      // Kullanıcıyı premium yap
      const userRef = db.collection("users").doc(userId);
      
      // 🔄 Premium aktivasyonu: Günlük faydalar veriliyor
      batch.update(userRef, {
        isPremium: true,
        premiumType: premiumType,
        premiumUntil: subscriptionData.endDate,
        dailyRewindsRemaining: 3, // 🔄 Günde 3 geri alma hakkı
        dailyChatRequestsRemaining: 999, // 💬 Sınırsız chat
        lastDailyReset: now,
        updatedAt: now,
      });
      
      activatedCount++;
      console.log(`✅ Premium aktif edildi: ${userId} (${premiumType}) - günlük faydalar: unlimited chats + 3 rewinds`);
      console.log(`💬 Super Chat'ler IAP sistemiyle yönetiliyor (superChatsRemaining)`);
    }
    
    await batch.commit();
    
    console.log(`🎫 ${activatedCount} kuyruklu premium aboneliği aktif edildi`);
    
    // Log kaydet
    await db.collection("system_logs").add({
      type: "premium_queue_activation",
      timestamp: now,
      activatedCount: activatedCount,
      status: "completed"
    });
    
    return { success: true, activatedCount };
    
  } catch (error) {
    console.error("❌ Premium kuyruk aktivasyon hatası:", error);
    
    await db.collection("system_logs").add({
      type: "premium_queue_activation_error",
      timestamp: now,
      error: error.message,
      status: "failed"
    });
    
    throw error;
  }
}

// EMAIL DEĞİŞTİRME DOĞRULAma KODU GÖNDERİMİ
exports.sendEmailChangeVerification = onCall(
  {
    region: "us-central1",
    cors: true,
    enforceAppCheck: false,
  },
  async (request) => {
    requireAuth(request);
    const {newEmail, code} = request.data;
    const userName = escapeHtml(request.data.userName);
    
    console.log(`📧 Email değiştirme doğrulama kodu gönderiliyor: ${newEmail}, Kod: ${code}`);
    
    // Input validation
    if (!newEmail || !code || !userName) {
      console.error("Eksik parametreler");
      return {success: false, error: "Email, kod ve kullanıcı adı gerekli"};
    }
    
    // Email format validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(newEmail)) {
      console.error("Geçersiz email formatı:", newEmail);
      return {success: false, error: "Geçersiz email formatı"};
    }
    
    const resend = new Resend(resendKey.value());
    
    try {
      const {data, error} = await resend.emails.send({
        from: "noreply@lovenme.app", 
        to: newEmail,
        subject: "🔐 LoveNMe - Email Adresinizi Doğrulayın",
        html: `
          <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 40px; text-align: center; border-radius: 10px 10px 0 0;">
              <h1 style="color: white; margin: 0; font-size: 28px;">LoveNMe</h1>
              <p style="color: rgba(255,255,255,0.9); margin-top: 10px;">Email Adresinizi Değiştiriyorsunuz</p>
            </div>
            <div style="background: white; padding: 40px; border: 1px solid #e0e0e0; border-radius: 0 0 10px 10px;">
              <h2 style="color: #333; margin-top: 0;">Merhaba ${userName}!</h2>
              <p style="color: #666; font-size: 16px;">Yeni email adresinizi doğrulamak için aşağıdaki kodu kullanın:</p>
              <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 25px; text-align: center; margin: 30px 0; border-radius: 8px;">
                <span style="font-size: 42px; font-weight: bold; color: white; letter-spacing: 8px; font-family: monospace;">
                  ${code}
                </span>
              </div>
              <p style="color: #999; font-size: 14px; margin-top: 30px;">
                ⏱️ Bu kod 10 dakika geçerlidir.<br>
                🔒 Bu kodu kimseyle paylaşmayın.<br>
                📧 Email adresiniz onaylandıktan sonra güncellenecektir.
              </p>
              <hr style="border: none; border-top: 1px solid #e0e0e0; margin: 30px 0;">
              <p style="color: #999; font-size: 12px;">
                Bu email değiştirme işlemini siz başlatmadıysanız, lütfen hesabınızın güvenliğini kontrol edin.
              </p>
            </div>
            <div style="text-align: center; padding: 20px; color: #999; font-size: 12px;">
              © 2026 LoveNMe. Tüm hakları saklıdır.<br>
              <a href="https://lovenme.app" style="color: #667eea; text-decoration: none;">lovenme.app</a>
            </div>
          </div>
        `,
      });
      
      if (error) {
        console.error("Resend hatası:", error);
        return {success: false, error: error.message};
      }
      
      console.log(`✅ Email değiştirme doğrulama kodu gönderildi: ${data.id}`);
      return {success: true, messageId: data.id};
    } catch (error) {
      console.error("Email gönderim hatası:", error);
      return {success: false, error: "Email gönderilemedi"};
    }
  }
);

// ŞİFRE DEĞİŞTİRME DOĞRULAma KODU GÖNDERİMİ
exports.sendPasswordChangeVerification = onCall(
  {
    region: "us-central1",
    cors: true,
    enforceAppCheck: false,
  },
  async (request) => {
    requireAuth(request);
    const {email, code} = request.data;
    const userName = escapeHtml(request.data.userName);
    
    console.log(`📧 Şifre değiştirme doğrulama kodu gönderiliyor: ${email}, Kod: ${code}`);
    
    // Input validation
    if (!email || !code || !userName) {
      console.error("Eksik parametreler");
      return {success: false, error: "Email, kod ve kullanıcı adı gerekli"};
    }
    
    // Email format validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      console.error("Geçersiz email formatı:", email);
      return {success: false, error: "Geçersiz email formatı"};
    }
    
    const resend = new Resend(resendKey.value());
    
    try {
      const {data, error} = await resend.emails.send({
        from: "noreply@lovenme.app", 
        to: email,
        subject: "🔐 LoveNMe - Şifrenizi Değiştiriyorsunuz",
        html: `
          <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 40px; text-align: center; border-radius: 10px 10px 0 0;">
              <h1 style="color: white; margin: 0; font-size: 28px;">LoveNMe</h1>
              <p style="color: rgba(255,255,255,0.9); margin-top: 10px;">Şifre Değiştirme Doğrulaması</p>
            </div>
            <div style="background: white; padding: 40px; border: 1px solid #e0e0e0; border-radius: 0 0 10px 10px;">
              <h2 style="color: #333; margin-top: 0;">Merhaba ${userName}!</h2>
              <p style="color: #666; font-size: 16px;">Şifrenizi değiştirmek için aşağıdaki kodu kullanın:</p>
              <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 25px; text-align: center; margin: 30px 0; border-radius: 8px;">
                <span style="font-size: 42px; font-weight: bold; color: white; letter-spacing: 8px; font-family: monospace;">
                  ${code}
                </span>
              </div>
              <p style="color: #999; font-size: 14px; margin-top: 30px;">
                ⏱️ Bu kod 10 dakika geçerlidir.<br>
                🔒 Bu kodu kimseyle paylaşmayın.<br>
                🛡️ Şifreniz onaylandıktan sonra güncellenecektir.
              </p>
              <hr style="border: none; border-top: 1px solid #e0e0e0; margin: 30px 0;">
              <p style="color: #999; font-size: 12px;">
                Bu şifre değiştirme işlemini siz başlatmadıysanız, lütfen hesabınızın güvenliğini kontrol edin ve derhal bizimle iletişime geçin.
              </p>
            </div>
            <div style="text-align: center; padding: 20px; color: #999; font-size: 12px;">
              © 2026 LoveNMe. Tüm hakları saklıdır.<br>
              <a href="https://lovenme.app" style="color: #667eea; text-decoration: none;">lovenme.app</a>
            </div>
          </div>
        `,
      });
      
      if (error) {
        console.error("Resend hatası:", error);
        return {success: false, error: error.message};
      }
      
      console.log(`✅ Şifre değiştirme doğrulama kodu gönderildi: ${data.id}`);
      return {success: true, messageId: data.id};
    } catch (error) {
      console.error("Email gönderim hatası:", error);
      return {success: false, error: "Email gönderilemedi"};
    }
  }
);

// ============================================================
// PASSWORD RESET — ŞİFRE SIFIRLAMA
// ============================================================
// GÜVENLİK NOTU (bilerek böyle):
// Kod SUNUCUDA üretilir, düz metin değil hash olarak saklanır, deneme sayısı
// sayılır ve `password_reset_codes` koleksiyonu firestore.rules ile tamamen
// kapalıdır (yalnızca Admin SDK yazar/okur). Daha önce kodu istemci üretip
// dünyaya açık bir dokümana yazıyordu; bu, kimlik doğrulaması gerektirmeyen
// tam hesap ele geçirmeye izin veriyordu.
// Ayrıca hesabın var olup olmadığı SIZDIRILMAZ — e-posta adresleri bu uç
// nokta üzerinden taranamasın diye her durumda aynı yanıt döner.

const RESET_CODE_TTL_MS = 5 * 60 * 1000; // 5 dakika
const RESET_RESEND_COOLDOWN_MS = 60 * 1000; // 60 saniye
const RESET_MAX_ATTEMPTS = 5;
const RESET_EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** E-postayı doküman kimliği ve karşılaştırma için normalize eder. */
function normalizeEmail(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

/** Kodu düz metin saklamamak için e-posta ile tuzlanmış SHA-256. */
function hashResetCode(email, code) {
  return crypto.createHash("sha256").update(email + ":" + code).digest("hex");
}

/** Zamanlama saldırısına kapalı hex karşılaştırma. */
function safeEqualHex(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) {
    return false;
  }
  try {
    return crypto.timingSafeEqual(Buffer.from(a, "hex"), Buffer.from(b, "hex"));
  } catch (_) {
    return false;
  }
}

exports.sendPasswordResetEmail = onCall(
  {
    region: "us-central1",
    cors: true,
    enforceAppCheck: false,
  },
  async (request) => {
    const email = normalizeEmail(request.data && request.data.email);

    if (!email || !RESET_EMAIL_REGEX.test(email)) {
      return {success: false, error: "Geçersiz email formatı"};
    }

    // Hesabın varlığını sızdırmamak için kullanılan ortak yanıt.
    const genericOk = {success: true};

    const db = getFirestore();
    const ref = db.collection("password_reset_codes").doc(email);

    try {
      // Yeniden gönderim soğuma süresi — sunucu tarafında zorunlu.
      const existing = await ref.get();
      if (existing.exists) {
        const createdAtMs = existing.data().createdAtMs || 0;
        if (Date.now() - createdAtMs < RESET_RESEND_COOLDOWN_MS) {
          return {
            success: false,
            error: "Çok sık denediniz. Lütfen bir dakika bekleyin.",
            cooldown: true,
          };
        }
      }

      let userRecord = null;
      try {
        userRecord = await getAuth().getUserByEmail(email);
      } catch (_) {
        userRecord = null;
      }

      // Kullanıcı yoksa e-posta göndermeyiz ama yine de başarı döneriz:
      // aksi halde bu uç nokta bir e-posta doğrulayıcıya dönüşür.
      if (!userRecord) {
        console.log("Şifre sıfırlama: kayıtlı olmayan adres için istek");
        return genericOk;
      }

      const code = String(crypto.randomInt(100000, 1000000));

      await ref.set({
        email: email,
        codeHash: hashResetCode(email, code),
        createdAtMs: Date.now(),
        expiresAt: Date.now() + RESET_CODE_TTL_MS,
        attempts: 0,
      });

      const resend = new Resend(resendKey.value());
      const {error} = await resend.emails.send({
        from: "noreply@lovenme.app",
        to: email,
        subject: "🔒 LoveNMe - Şifre Sıfırlama Kodu",
        html: buildResetCodeEmailHtml(code),
      });

      if (error) {
        console.error("Resend hatası:", error);
        return {success: false, error: "Email gönderilemedi"};
      }

      console.log("✅ Şifre sıfırlama kodu gönderildi");
      return genericOk;
    } catch (error) {
      console.error("Şifre sıfırlama isteği hatası:", error);
      return {success: false, error: "İşlem tamamlanamadı"};
    }
  }
);

// RESET USER PASSWORD - KULLANICI ŞİFRESİNİ SIFIRLA
exports.resetUserPassword = onCall(
  {
    region: "us-central1",
    cors: true,
    enforceAppCheck: false,
  },
  async (request) => {
    const email = normalizeEmail(request.data && request.data.email);
    const verificationCode = String(
      (request.data && request.data.verificationCode) || ""
    ).trim();
    const newPassword = request.data && request.data.newPassword;

    if (!email || !newPassword || !verificationCode) {
      return {
        success: false,
        error: "Email, yeni şifre ve doğrulama kodu gerekli",
      };
    }

    if (typeof newPassword !== "string" || newPassword.length < 6) {
      return {success: false, error: "Şifre en az 6 karakter olmalı"};
    }

    const db = getFirestore();
    const ref = db.collection("password_reset_codes").doc(email);

    try {
      const codeDoc = await ref.get();
      if (!codeDoc.exists) {
        return {success: false, error: "Doğrulama kodu bulunamadı"};
      }

      const codeData = codeDoc.data();

      if (Date.now() > (codeData.expiresAt || 0)) {
        await ref.delete();
        return {success: false, error: "Doğrulama kodunun süresi dolmuş"};
      }

      // Kaba kuvvet koruması: her hatalı denemeden sonra sayaç artar.
      const attempts = (codeData.attempts || 0) + 1;
      if (attempts > RESET_MAX_ATTEMPTS) {
        await ref.delete();
        return {
          success: false,
          error: "Çok fazla hatalı deneme. Lütfen yeni kod isteyin.",
        };
      }

      const expectedHash = hashResetCode(email, verificationCode);
      if (!safeEqualHex(codeData.codeHash, expectedHash)) {
        await ref.update({attempts: attempts});
        return {success: false, error: "Geçersiz doğrulama kodu"};
      }

      const userRecord = await getAuth().getUserByEmail(email);
      if (!userRecord) {
        return {success: false, error: "Kullanıcı bulunamadı"};
      }

      await getAuth().updateUser(userRecord.uid, {password: newPassword});

      // Çalınmış oturumların devam etmemesi için yenileme jetonlarını iptal et.
      await getAuth().revokeRefreshTokens(userRecord.uid);

      await ref.delete();

      console.log("✅ Şifre başarıyla güncellendi");
      return {success: true, message: "Şifre başarıyla güncellendi"};
    } catch (error) {
      console.error("Şifre güncelleme hatası:", error);
      return {success: false, error: "Şifre güncellenemedi"};
    }
  }
);

/**
 * Şifre sıfırlama e-postasının gövdesi.
 * Buraya YALNIZCA sunucuda üretilmiş kod girer; çağıranın gönderdiği hiçbir
 * metin HTML'e gömülmez (eskiden `userName` doğrudan gömülüyordu ve bu bir
 * HTML enjeksiyon yüzeyiydi).
 */
function buildResetCodeEmailHtml(code) {
  return [
    '<div style="font-family: -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica Neue, Arial, sans-serif; max-width: 600px; margin: 0 auto;">',
    '<div style="background: linear-gradient(135deg, #E91E63 0%, #AD1457 100%); padding: 40px; text-align: center; border-radius: 10px 10px 0 0;">',
    '<h1 style="color: white; margin: 0; font-size: 28px;">LoveNMe</h1>',
    '<p style="color: rgba(255,255,255,0.9); margin-top: 10px;">Şifre Sıfırlama</p>',
    "</div>",
    '<div style="background: white; padding: 40px; border: 1px solid #e0e0e0; border-radius: 0 0 10px 10px;">',
    '<h2 style="color: #333; margin-top: 0;">Merhaba!</h2>',
    '<p style="color: #666; font-size: 16px;">Şifrenizi sıfırlamak için aşağıdaki doğrulama kodunu kullanın:</p>',
    '<div style="background: linear-gradient(135deg, #E91E63 0%, #AD1457 100%); padding: 25px; text-align: center; margin: 30px 0; border-radius: 8px;">',
    '<span style="font-size: 42px; font-weight: bold; color: white; letter-spacing: 8px; font-family: monospace;">',
    code,
    "</span>",
    "</div>",
    '<div style="background: #fff3cd; border: 1px solid #ffeaa7; padding: 15px; border-radius: 8px; margin: 20px 0;">',
    '<p style="color: #856404; margin: 0; font-size: 14px;">',
    "<strong>⚠️ Güvenlik Uyarısı:</strong><br>",
    "• Bu kodu sadece LoveNMe uygulamasında kullanın<br>",
    "• Kodu kimseyle paylaşmayın<br>",
    "• Şüpheli aktivite fark ederseniz derhal şifrenizi değiştirin",
    "</p>",
    "</div>",
    '<p style="color: #999; font-size: 14px; margin-top: 30px;">',
    "⏱️ Bu kod 5 dakika geçerlidir.<br>",
    "🔒 Kod doğrulandıktan sonra yeni şifrenizi belirleyebilirsiniz.",
    "</p>",
    '<hr style="border: none; border-top: 1px solid #e0e0e0; margin: 30px 0;">',
    '<p style="color: #999; font-size: 12px;">',
    "Bu şifre sıfırlama işlemini siz başlatmadıysanız, bu emaili görmezden gelebilirsiniz.<br>",
    "Hesabınızın güvenliğinden endişe ediyorsanız, lütfen bizimle iletişime geçin.",
    "</p>",
    "</div>",
    '<div style="text-align: center; padding: 20px; color: #999; font-size: 12px;">',
    "© 2026 LoveNMe. Tüm hakları saklıdır.<br>",
    '<a href="https://lovenme.app" style="color: #E91E63; text-decoration: none;">lovenme.app</a>',
    "</div>",
    "</div>",
  ].join("");
}

// NOT: searchPlaces ve getPlaceDetails kaldirildi (30.08.2026).
// Ikisi de kimlik dogrulamasiz acik uc noktaydi (getPlaceDetails ayrica
// onRequest + cors({origin:true}) idi) ve Places faturasini herkese aciyordu.
// Istemcide hicbir cagirani yoktu; bot altyapisi icin yazilmislardi.

// 🛡️ GOOGLE PLAY PURCHASE VERIFICATION - Sunucu taraflı satın alma doğrulaması
exports.verifyGooglePlayPurchase = onCall(
  {
    region: "us-central1",
    enforceAppCheck: false,
    secrets: [googleServiceAccountKey],
  },
  async (request) => {
    if (!request.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Kimlik doğrulama gerekli");
    }

    const {purchaseToken, productId, purchaseType} = request.data;

    if (!purchaseToken || !productId || !purchaseType) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "purchaseToken, productId ve purchaseType gerekli"
      );
    }

    if (purchaseType !== "product" && purchaseType !== "subscription") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "purchaseType 'product' veya 'subscription' olmalı"
      );
    }

    const packageName = "com.lovenme.app";
    const userId = request.auth.uid;

    console.log(`🛡️ Purchase doğrulama başlatıldı: userId=${userId}, productId=${productId}, type=${purchaseType}`);

    try {
      // Service account JSON'unu secret'tan oku
      const serviceAccountJson = JSON.parse(googleServiceAccountKey.value());

      // Google Play Developer API için kimlik doğrulama
      const auth = new GoogleAuth({
        credentials: serviceAccountJson,
        scopes: ["https://www.googleapis.com/auth/androidpublisher"],
      });
      const client = await auth.getClient();
      const tokenResponse = await client.getAccessToken();
      const accessToken = tokenResponse.token;

      let apiUrl;
      if (purchaseType === "subscription") {
        apiUrl = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}/purchases/subscriptions/${productId}/tokens/${purchaseToken}`;
      } else {
        apiUrl = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}/purchases/products/${productId}/tokens/${purchaseToken}`;
      }

      const response = await axios.get(apiUrl, {
        headers: {Authorization: `Bearer ${accessToken}`},
      });

      const data = response.data;
      let isValid = false;
      let reason = "";

      if (purchaseType === "subscription") {
        // paymentState: 1 = ödendi, 2 = ücretsiz deneme
        isValid = data.paymentState === 1 || data.paymentState === 2;
        reason = isValid ? "Abonelik doğrulandı" : `Geçersiz ödeme durumu: ${data.paymentState}`;
      } else {
        // purchaseState: 0 = satın alındı, 4 = önceden onaylandı
        isValid = data.purchaseState === 0 || data.purchaseState === 4;
        reason = isValid ? "Satın alma doğrulandı" : `Geçersiz satın alma durumu: ${data.purchaseState}`;
      }

      // Doğrulama sonucunu Firestore'a logla
      await getFirestore().collection("purchase_verifications").add({
        userId: userId,
        productId: productId,
        purchaseType: purchaseType,
        isValid: isValid,
        reason: reason,
        purchaseToken: purchaseToken.substring(0, 20) + "...", // Güvenlik için token'ı kısalt
        verifiedAt: FieldValue.serverTimestamp(),
        rawData: {
          purchaseState: data.purchaseState !== undefined ? data.purchaseState : null,
          paymentState: data.paymentState !== undefined ? data.paymentState : null,
          orderId: data.orderId !== undefined ? data.orderId : null,
        },
      });

      console.log(`✅ Purchase doğrulama tamamlandı: userId=${userId}, isValid=${isValid}, reason=${reason}`);

      return {valid: isValid, reason, productId, purchaseType};
    } catch (error) {
      const statusCode = error.response ? error.response.status : null;
      const errorMessage = error.response
        ? JSON.stringify(error.response.data)
        : error.message;

      console.error(`❌ Purchase doğrulama hatası: userId=${userId}, productId=${productId}`, errorMessage);

      // 404 = Token geçersiz veya zaten tüketilmiş
      if (statusCode === 404) {
        return {valid: false, reason: "Satın alma token'ı bulunamadı veya geçersiz"};
      }

      // 410 = Token zaten kullanılmış (consumable için normal)
      // ✅ FIX: Consumable ürünler acknowledge edildikten sonra 410 döner — bu meşru
      if (statusCode === 410) {
        if (purchaseType === "product") {
          console.log(`ℹ️ Consumable token 410 (acknowledged) — valid kabul ediliyor: ${productId}`);
          return {valid: true, reason: "Consumable satın alma zaten onaylanmış (410)"};
        }
        return {valid: false, reason: "Satın alma token'ı zaten kullanılmış"};
      }

      throw new functions.https.HttpsError(
        "internal",
        `Doğrulama başarısız: ${errorMessage}`
      );
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 🔔 GOOGLE PLAY REAL-TIME DEVELOPER NOTIFICATIONS (RTDN)
// ─────────────────────────────────────────────────────────────────────────────
// Google Play Pub/Sub'dan gelen iade/iptal/subscription değişiklik bildirimleri.
// Cloud Console'da yapılması gerekenler:
//   1. Pub/Sub topic oluştur: "play-rtdn"
//   2. Google Play Console > Monetization > Monetization setup > Real-time developer notifications
//      Topic name: projects/<PROJECT_ID>/topics/play-rtdn
//   3. Bu Cloud Function'ın URL'sini Pub/Sub push subscription olarak ekle
//      VEYA Pub/Sub pull subscription kullan (aşağıdaki onRequest handler push için)
// ─────────────────────────────────────────────────────────────────────────────
exports.handlePlayRTDN = onRequest(
  {
    region: "us-central1",
    secrets: [googleServiceAccountKey],
  },
  async (req, res) => {
    // Sadece POST kabul et
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    // GÜVENLİK: Bu uç nokta eskiden HİÇBİR doğrulama yapmıyordu — herkes
    // sahte bir "iade edildi" bildirimi POST'layıp istediği kullanıcının
    // premium'unu iptal ettirebiliyordu. Pub/Sub push aboneliği OIDC ile
    // imzalanmalı ve imza burada doğrulanmalı.
    // NOT: Doğrulanmamış push reddedilse bile iadeler kaybolmaz; günlük
    // checkVoidedPurchases işi Play Voided Purchases API'sini ayrıca tarar.
    const rtdnAuthOk = await verifyPubSubPush(req);
    if (!rtdnAuthOk) {
      console.error("❌ RTDN: imzasiz veya gecersiz push reddedildi");
      res.status(403).send("Forbidden");
      return;
    }

    try {
      // Pub/Sub mesajını decode et
      const message = req.body.message;
      if (!message || !message.data) {
        console.warn("⚠️ RTDN: Geçersiz Pub/Sub mesajı");
        res.status(400).send("Invalid message");
        return;
      }

      const dataStr = Buffer.from(message.data, "base64").toString("utf-8");
      const notification = JSON.parse(dataStr);
      const packageName = notification.packageName || "";

      console.log(`🔔 RTDN alındı: package=${packageName}`, JSON.stringify(notification));

      // com.lovenme.app kontrolü
      if (packageName !== "com.lovenme.app") {
        console.warn(`⚠️ RTDN: Farklı paket adı: ${packageName}`);
        res.status(200).send("OK (ignored)");
        return;
      }

      const db = getFirestore();

      // RTDN log kaydet
      await db.collection("rtdn_notifications").add({
        notification: notification,
        receivedAt: FieldValue.serverTimestamp(),
        processed: false,
      });

      // ───── SUBSCRIPTION BİLDİRİMİ ─────
      if (notification.subscriptionNotification) {
        const subNotif = notification.subscriptionNotification;
        const notificationType = subNotif.notificationType;
        const purchaseToken = subNotif.purchaseToken;
        const subscriptionId = subNotif.subscriptionId;

        console.log(`📋 Subscription RTDN: type=${notificationType}, product=${subscriptionId}`);

        // notificationType değerleri:
        // 1 = SUBSCRIPTION_RECOVERED (ödeme kurtarıldı)
        // 2 = SUBSCRIPTION_RENEWED (yenilendi)
        // 3 = SUBSCRIPTION_CANCELED (iptal edildi — dönem sonunda biter)
        // 4 = SUBSCRIPTION_PURCHASED (yeni satın alma)
        // 5 = SUBSCRIPTION_ON_HOLD (ödeme beklemede)
        // 6 = SUBSCRIPTION_IN_GRACE_PERIOD (grace period)
        // 7 = SUBSCRIPTION_RESTARTED (yeniden başlatıldı)
        // 12 = SUBSCRIPTION_REVOKED (iade — hemen iptal)
        // 13 = SUBSCRIPTION_EXPIRED (süresi doldu)

        // İade (REVOKED) — en kritik: premium hemen geri alınmalı
        if (notificationType === 12) {
          console.log(`💸 SUBSCRIPTION REVOKED (iade): token=${purchaseToken ? purchaseToken.substring(0, 20) : "N/A"}...`);
          await _handleSubscriptionRevoked(db, purchaseToken, subscriptionId);
        }

        // Süresi doldu (EXPIRED)
        if (notificationType === 13) {
          console.log(`⏰ SUBSCRIPTION EXPIRED: token=${purchaseToken ? purchaseToken.substring(0, 20) : "N/A"}...`);
          await _handleSubscriptionExpired(db, purchaseToken, subscriptionId);
        }

        // İptal edildi (ama dönem sonuna kadar aktif kalır)
        if (notificationType === 3) {
          console.log(`🚫 SUBSCRIPTION CANCELED: token=${purchaseToken ? purchaseToken.substring(0, 20) : "N/A"}...`);
          await _handleSubscriptionCanceled(db, purchaseToken, subscriptionId);
        }

        // Yenilendi
        if (notificationType === 2) {
          console.log(`🔄 SUBSCRIPTION RENEWED: token=${purchaseToken ? purchaseToken.substring(0, 20) : "N/A"}...`);
          await _handleSubscriptionRenewed(db, purchaseToken, subscriptionId);
        }
      }

      // ───── ONE-TIME PRODUCT (CONSUMABLE) BİLDİRİMİ ─────
      if (notification.oneTimeProductNotification) {
        const otpNotif = notification.oneTimeProductNotification;
        const notificationType = otpNotif.notificationType;
        const purchaseToken = otpNotif.purchaseToken;
        const sku = otpNotif.sku;

        console.log(`📋 OneTimeProduct RTDN: type=${notificationType}, sku=${sku}`);

        // notificationType:
        // 1 = ONE_TIME_PRODUCT_PURCHASED
        // 2 = ONE_TIME_PRODUCT_CANCELED (iade)
        if (notificationType === 2) {
          console.log(`💸 CONSUMABLE REFUNDED: sku=${sku}, token=${purchaseToken ? purchaseToken.substring(0, 20) : "N/A"}...`);
          await _handleConsumableRefund(db, purchaseToken, sku);
        }
      }

      // ───── VOIDED PURCHASE BİLDİRİMİ ─────
      if (notification.voidedPurchaseNotification) {
        const vpNotif = notification.voidedPurchaseNotification;
        console.log(`💸 VOIDED PURCHASE: orderId=${vpNotif.orderId}`);
        await _handleVoidedPurchase(db, vpNotif);
      }

      // İşlendiğini işaretle
      const rtdnDocs = await db.collection("rtdn_notifications")
        .where("processed", "==", false)
        .orderBy("receivedAt", "desc")
        .limit(1)
        .get();
      if (!rtdnDocs.empty) {
        await rtdnDocs.docs[0].ref.update({processed: true});
      }

      res.status(200).send("OK");
    } catch (error) {
      console.error("❌ RTDN işleme hatası:", error);
      // Yine de 200 dön, yoksa Pub/Sub tekrar tekrar gönderir
      res.status(200).send("OK (error logged)");
    }
  }
);

// ─────── RTDN YARDIMCI FONKSİYONLAR ───────

// 🔍 Purchase token'dan userId'yi bul
async function _findUserByPurchaseToken(db, purchaseToken) {
  // purchases collection'da token ara
  const shortToken = purchaseToken ? purchaseToken.substring(0, 20) + "..." : "";

  // Önce purchase_verifications'da ara (tam token kısaltılmış hali saklanıyor)
  // Ama asıl purchases collection'da verificationData alanında token saklanabilir
  const purchasesSnap = await db.collection("purchases")
    .where("verificationData", "==", purchaseToken)
    .limit(1)
    .get();

  if (!purchasesSnap.empty) {
    return purchasesSnap.docs[0].data().userId;
  }

  // purchase_verifications'da ara (kısaltılmış token saklanıyor, tam eşleşme olmaz)
  // Fallback: Son 24 saatteki tüm doğrulamaları kontrol et
  const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const verSnap = await db.collection("purchase_verifications")
    .where("verifiedAt", ">=", oneDayAgo)
    .orderBy("verifiedAt", "desc")
    .limit(100)
    .get();

  for (const doc of verSnap.docs) {
    const data = doc.data();
    // token ilk 20 karakter + "..." olarak saklandı
    if (purchaseToken && data.purchaseToken === shortToken) {
      return data.userId;
    }
  }

  console.warn(`⚠️ Token ile userId bulunamadı: ${shortToken}`);
  return null;
}

// 💸 Subscription iade (REVOKED) — premium hemen geri al
async function _handleSubscriptionRevoked(db, purchaseToken, subscriptionId) {
  try {
    const userId = await _findUserByPurchaseToken(db, purchaseToken);
    if (!userId) {
      console.error("❌ REVOKED: userId bulunamadı — manual review gerekiyor");
      await _logRefundEvent(db, "subscription_revoked_no_user", null, subscriptionId, purchaseToken);
      return;
    }

    console.log(`💸 Premium geri alınıyor: userId=${userId}, product=${subscriptionId}`);

    // Premium'u hemen kapat
    await db.collection("users").doc(userId).update({
      isPremium: false,
      premiumType: null,
      premiumUntil: null,
      dailyChatRequestsRemaining: 5,
      premiumRevokedAt: FieldValue.serverTimestamp(),
      premiumRevokeReason: "google_play_refund",
    });

    // Purchase kaydını güncelle
    await _markPurchasesRefunded(db, userId, subscriptionId);

    // Log
    await _logRefundEvent(db, "subscription_revoked", userId, subscriptionId, purchaseToken);

    console.log(`✅ Premium geri alındı: userId=${userId}`);
  } catch (error) {
    console.error("❌ _handleSubscriptionRevoked hatası:", error);
  }
}

// ⏰ Subscription süresi doldu (EXPIRED)
// eslint-disable-next-line no-unused-vars
async function _handleSubscriptionExpired(db, purchaseToken, subscriptionId) {
  try {
    const userId = await _findUserByPurchaseToken(db, purchaseToken);
    if (!userId) return;

    // checkPremiumStatus zaten saat başı kontrol ediyor,
    // ama RTDN ile anında da kapatmak daha iyi
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) return;

    const userData = userDoc.data();
    if (userData.isPremium) {
      await db.collection("users").doc(userId).update({
        isPremium: false,
        premiumType: null,
        premiumUntil: null,
        dailyChatRequestsRemaining: 5,
        premiumExpiredAt: FieldValue.serverTimestamp(),
      });
      console.log(`⏰ Premium expired via RTDN: userId=${userId}`);
    }
  } catch (error) {
    console.error("❌ _handleSubscriptionExpired hatası:", error);
  }
}

// 🚫 Subscription iptal edildi (dönem sonuna kadar aktif kalır)
async function _handleSubscriptionCanceled(db, purchaseToken, subscriptionId) {
  try {
    const userId = await _findUserByPurchaseToken(db, purchaseToken);
    if (!userId) return;

    // Sadece iptal durumunu logla — premium dönem sonuna kadar aktif kalır
    await db.collection("users").doc(userId).update({
      subscriptionCanceledAt: FieldValue.serverTimestamp(),
      subscriptionAutoRenew: false,
    });

    await _logRefundEvent(db, "subscription_canceled", userId, subscriptionId, purchaseToken);
    console.log(`🚫 Subscription iptal kaydedildi (dönem sonuna kadar aktif): userId=${userId}`);
  } catch (error) {
    console.error("❌ _handleSubscriptionCanceled hatası:", error);
  }
}

// 🔄 Subscription yenilendi
// eslint-disable-next-line no-unused-vars
async function _handleSubscriptionRenewed(db, purchaseToken, subscriptionId) {
  try {
    const userId = await _findUserByPurchaseToken(db, purchaseToken);
    if (!userId) return;

    // Yenileme logla
    await db.collection("users").doc(userId).update({
      subscriptionAutoRenew: true,
      subscriptionRenewedAt: FieldValue.serverTimestamp(),
    });

    console.log(`🔄 Subscription yenilendi: userId=${userId}`);
  } catch (error) {
    console.error("❌ _handleSubscriptionRenewed hatası:", error);
  }
}

// 💸 Consumable iade (elmas / super chat)
async function _handleConsumableRefund(db, purchaseToken, sku) {
  try {
    const userId = await _findUserByPurchaseToken(db, purchaseToken);
    if (!userId) {
      console.error("❌ CONSUMABLE REFUND: userId bulunamadı — manual review gerekiyor");
      await _logRefundEvent(db, "consumable_refund_no_user", null, sku, purchaseToken);
      return;
    }

    console.log(`💸 Consumable iade işleniyor: userId=${userId}, sku=${sku}`);

    // SKU'dan miktar ve tip belirle
    const refundInfo = _getRefundInfoFromSku(sku);
    if (!refundInfo) {
      console.error(`❌ Bilinmeyen SKU: ${sku}`);
      await _logRefundEvent(db, "consumable_refund_unknown_sku", userId, sku, purchaseToken);
      return;
    }

    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) return;
    const userData = userDoc.data();

    // Benefit geri al
    const updates = {updatedAt: FieldValue.serverTimestamp()};

    if (refundInfo.type === "diamonds") {
      const currentDiamonds = userData.diamonds || 0;
      // Negatife düşmesin
      const newBalance = Math.max(0, currentDiamonds - refundInfo.quantity);
      updates.diamonds = newBalance;
      updates.diamondCount = newBalance;
      console.log(`💎 Elmas geri alındı: ${refundInfo.quantity} (${currentDiamonds} → ${newBalance})`);
    } else if (refundInfo.type === "superChats") {
      const currentSC = userData.superChatsRemaining || 0;
      const newBalance = Math.max(0, currentSC - refundInfo.quantity);
      updates.superChatsRemaining = newBalance;
      console.log(`💬 Super Chat geri alındı: ${refundInfo.quantity} (${currentSC} → ${newBalance})`);
    }

    await db.collection("users").doc(userId).update(updates);

    // Purchase kaydını güncelle
    await _markPurchasesRefunded(db, userId, sku);

    // Log
    await _logRefundEvent(db, "consumable_refunded", userId, sku, purchaseToken);

    console.log(`✅ Consumable iade tamamlandı: userId=${userId}, sku=${sku}`);
  } catch (error) {
    console.error("❌ _handleConsumableRefund hatası:", error);
  }
}

// 💸 Voided Purchase (Google Play iade/chargeback)
async function _handleVoidedPurchase(db, vpNotif) {
  try {
    const orderId = vpNotif.orderId;
    const productType = vpNotif.productType; // 0 = subscription, 1 = one-time

    // orderId ile purchase kaydını bul
    const purchaseSnap = await db.collection("purchases")
      .where("orderId", "==", orderId)
      .limit(1)
      .get();

    if (purchaseSnap.empty) {
      // purchase_verifications'da da ara
      const verSnap = await db.collection("purchase_verifications")
        .where("rawData.orderId", "==", orderId)
        .limit(1)
        .get();

      if (!verSnap.empty) {
        const userId = verSnap.docs[0].data().userId;
        const productId = verSnap.docs[0].data().productId;
        await _logRefundEvent(db, "voided_purchase", userId, productId, orderId);
        console.log(`💸 Voided purchase logged: orderId=${orderId}, userId=${userId}`);
      } else {
        await _logRefundEvent(db, "voided_purchase_no_match", null, null, orderId);
      }
      return;
    }

    const purchaseData = purchaseSnap.docs[0].data();
    const userId = purchaseData.userId;
    const productId = purchaseData.productId;

    // Benefit geri al
    if (productType === 0) {
      // Subscription iade
      await _handleSubscriptionRevoked(db, null, productId);
    } else {
      // Consumable iade
      await _handleConsumableRefund(db, null, productId);
    }

    await _logRefundEvent(db, "voided_purchase_processed", userId, productId, orderId);
  } catch (error) {
    console.error("❌ _handleVoidedPurchase hatası:", error);
  }
}

// 📝 SKU'dan iade bilgisi çıkar
function _getRefundInfoFromSku(sku) {
  const skuMap = {
    "com.lovenme.diamonds.tenpack": {type: "diamonds", quantity: 10},
    "com.lovenme.diamonds.fiftypack": {type: "diamonds", quantity: 50},
    "com.lovenme.diamonds.hundredpack": {type: "diamonds", quantity: 100},
    "com.lovenme.diamonds.twfiftypack": {type: "diamonds", quantity: 250},
    "com.lovenme.diamonds.fivehundredpack": {type: "diamonds", quantity: 500},
    "com.lovenme.superchats.threepacks": {type: "superChats", quantity: 3},
    "com.lovenme.superchats.tenpacks": {type: "superChats", quantity: 10},
    "com.lovenme.superchats.twentyfivepacks": {type: "superChats", quantity: 25},
  };
  return skuMap[sku] || null;
}

// 📝 Purchase kayıtlarını "refunded" olarak işaretle
async function _markPurchasesRefunded(db, userId, productId) {
  try {
    const snap = await db.collection("purchases")
      .where("userId", "==", userId)
      .where("productId", "==", productId)
      .where("status", "==", "completed")
      .limit(5)
      .get();

    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.update(doc.ref, {
        status: "refunded",
        refundedAt: FieldValue.serverTimestamp(),
      });
    }
    if (!snap.empty) await batch.commit();
  } catch (error) {
    console.error("❌ _markPurchasesRefunded hatası:", error);
  }
}

// 📝 İade event'i logla
async function _logRefundEvent(db, type, userId, productId, token) {
  try {
    await db.collection("refund_events").add({
      type: type,
      userId: userId || null,
      productId: productId || null,
      token: token ? (token.length > 30 ? token.substring(0, 30) + "..." : token) : null,
      timestamp: FieldValue.serverTimestamp(),
      needsReview: !userId, // userId bulunamadıysa manual review gerekiyor
    });
  } catch (error) {
    console.error("❌ _logRefundEvent hatası:", error);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 🔍 VOIDED PURCHASES CHECKER — Günlük cron ile iade edilen alımları kontrol et
// ─────────────────────────────────────────────────────────────────────────────
// RTDN'in kaçırdığı iadeleri yakalamak için ek güvenlik katmanı.
// Google Play Voided Purchases API ile son 24 saatteki iadeleri kontrol eder.
// ─────────────────────────────────────────────────────────────────────────────
exports.checkVoidedPurchases = onSchedule({
  schedule: "0 3 * * *", // Her gün saat 03:00 (gece)
  timeZone: "Europe/Istanbul",
  region: "us-central1",
  secrets: [googleServiceAccountKey],
}, async () => {
  console.log("🔍 Voided purchases kontrolü başlatılıyor...");

  const db = getFirestore();
  const packageName = "com.lovenme.app";

  try {
    // Service account ile auth
    const serviceAccountJson = JSON.parse(googleServiceAccountKey.value());
    const auth = new GoogleAuth({
      credentials: serviceAccountJson,
      scopes: ["https://www.googleapis.com/auth/androidpublisher"],
    });
    const client = await auth.getClient();
    const tokenResponse = await client.getAccessToken();
    const accessToken = tokenResponse.token;

    // Son 24 saatteki voided purchases
    const startTimeMillis = Date.now() - (24 * 60 * 60 * 1000);
    const apiUrl = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}/purchases/voidedpurchases?startTime=${startTimeMillis}&maxResults=100`;

    const response = await axios.get(apiUrl, {
      headers: {Authorization: `Bearer ${accessToken}`},
    });

    const voidedPurchases = response.data.voidedPurchases || [];
    console.log(`🔍 ${voidedPurchases.length} voided purchase bulundu`);

    let processedCount = 0;

    for (const vp of voidedPurchases) {
      const orderId = vp.orderId;
      const purchaseToken = vp.purchaseToken;
      const productType = vp.purchaseType; // 0 = subscription, 1 = product

      // Daha önce işlenmiş mi kontrol et
      const existingSnap = await db.collection("refund_events")
        .where("token", "==", orderId)
        .where("type", "in", ["voided_purchase_processed", "subscription_revoked", "consumable_refunded"])
        .limit(1)
        .get();

      if (!existingSnap.empty) {
        continue; // Zaten işlenmiş
      }

      console.log(`💸 Voided purchase işleniyor: orderId=${orderId}, type=${productType}`);

      // Purchase token ile userId bul
      const userId = await _findUserByPurchaseToken(db, purchaseToken);

      if (!userId) {
        // orderId ile de dene
        const purchaseSnap = await db.collection("purchases")
          .where("orderId", "==", orderId)
          .limit(1)
          .get();

        if (!purchaseSnap.empty) {
          const pData = purchaseSnap.docs[0].data();
          if (productType === 0) {
            await _handleSubscriptionRevoked(db, purchaseToken, pData.productId);
          } else {
            await _handleConsumableRefund(db, purchaseToken, pData.productId);
          }
        } else {
          await _logRefundEvent(db, "voided_cron_no_match", null, null, orderId);
        }
        continue;
      }

      // userId bulundu — benefit geri al
      // productId'yi purchases'dan bul
      const purchaseSnap = await db.collection("purchases")
        .where("userId", "==", userId)
        .where("status", "==", "completed")
        .orderBy("createdAt", "desc")
        .limit(10)
        .get();

      if (!purchaseSnap.empty) {
        const pData = purchaseSnap.docs[0].data();
        if (productType === 0) {
          await _handleSubscriptionRevoked(db, purchaseToken, pData.productId);
        } else {
          await _handleConsumableRefund(db, purchaseToken, pData.productId);
        }
      }

      processedCount++;
    }

    // Log
    await db.collection("system_logs").add({
      type: "voided_purchases_check",
      timestamp: new Date(),
      totalFound: voidedPurchases.length,
      processedCount: processedCount,
      status: "completed",
    });

    console.log(`✅ Voided purchases kontrolü tamamlandı: ${processedCount}/${voidedPurchases.length} işlendi`);
  } catch (error) {
    console.error("❌ Voided purchases kontrolü hatası:", error);

    // 404 = API etkin değil (normal, Play Console'da etkinleştirilmeli)
    if (error.response && error.response.status === 404) {
      console.warn("⚠️ Voided Purchases API etkin değil. Google Play Console'dan etkinleştirin.");
    }

    await db.collection("system_logs").add({
      type: "voided_purchases_check",
      timestamp: new Date(),
      error: error.message,
      status: "failed",
    });
  }
});

// ============================================================
// 📱 NETGSM SMS OTP — CLOUD FUNCTIONS (güvenli, server-side)
// Credentials: Firebase Functions config ile env'den okunur
// ============================================================

/**
 * sendOtpSms — OTP kodu oluştur ve NetGSM ile gönder
 * Client sadece telefon numarası gönderir, credentials server'da kalır
 */
exports.sendOtpSms = onCall({region: "europe-west1"}, async (request) => {
  // Auth kontrolü
  if (!request.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Giriş yapmalısınız.");
  }

  const {phoneNumber} = request.data;
  if (!phoneNumber) {
    throw new functions.https.HttpsError("invalid-argument", "Telefon numarası gerekli.");
  }

  // Telefon numarasını temizle
  let cleanPhone = phoneNumber.replace(/[^\d+]/g, "");
  if (!cleanPhone.startsWith("+")) {
    if (cleanPhone.startsWith("90")) {
      cleanPhone = "+" + cleanPhone;
    } else if (cleanPhone.startsWith("0")) {
      cleanPhone = "+90" + cleanPhone.substring(1);
    } else {
      cleanPhone = "+90" + cleanPhone;
    }
  }

  // Rate limiting: aynı numaraya 60 saniyede 1'den fazla SMS gönderme
  const db = getFirestore();
  const recentOtp = await db.collection("otp_codes")
      .where("phoneNumber", "==", cleanPhone)
      .where("createdAt", ">", new Date(Date.now() - 60 * 1000))
      .limit(1)
      .get();

  if (!recentOtp.empty) {
    throw new functions.https.HttpsError("resource-exhausted", "Lütfen 60 saniye bekleyin.");
  }

  // 6 haneli OTP kodu oluştur
  const otpCode = String(100000 + Math.floor(Math.random() * 900000));

  // OTP kodunu Firestore'a kaydet (5 dk geçerli)
  await db.collection("otp_codes").add({
    phoneNumber: cleanPhone,
    code: otpCode,
    userId: request.auth.uid,
    createdAt: new Date(),
    expiresAt: new Date(Date.now() + 5 * 60 * 1000),
    verified: false,
  });

  // NetGSM API ile SMS gönder
  const message = `Lovenme doğrulama kodunuz: ${otpCode}\n\nBu kodu kimseyle paylaşmayın.`;
  const smsPhone = cleanPhone.replace("+", "");

  const params = new URLSearchParams({
    usercode: netgsmUsercode.value(),
    password: netgsmPassword.value(),
    gsmno: smsPhone,
    message: message,
    msgheader: netgsmHeader.value(),
  });

  try {
    const smsResponse = await axios.get(
        `https://api.netgsm.com.tr/sms/send/get/?${params.toString()}`,
    );

    const body = (smsResponse.data || "").toString().trim();

    if (body.startsWith("00") || body.startsWith("01") || body.startsWith("02")) {
      console.log(`✅ OTP SMS gönderildi: ${cleanPhone}`);
      return {success: true};
    } else {
      console.error(`❌ NetGSM hata: ${body}`);
      throw new functions.https.HttpsError("internal", "SMS gönderilemedi.");
    }
  } catch (error) {
    console.error("❌ NetGSM API hatası:", error.message);
    throw new functions.https.HttpsError("internal", "SMS servisi hatası.");
  }
});

/**
 * verifyOtpSms — OTP kodunu server-side doğrula
 * Client hiçbir zaman OTP kodunu doğrudan göremez
 */
exports.verifyOtpSms = onCall({region: "europe-west1"}, async (request) => {
  if (!request.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Giriş yapmalısınız.");
  }

  const {phoneNumber, otpCode} = request.data;
  if (!phoneNumber || !otpCode) {
    throw new functions.https.HttpsError("invalid-argument", "Telefon ve kod gerekli.");
  }

  let cleanPhone = phoneNumber.replace(/[^\d+]/g, "");
  if (!cleanPhone.startsWith("+")) {
    if (cleanPhone.startsWith("90")) {
      cleanPhone = "+" + cleanPhone;
    } else if (cleanPhone.startsWith("0")) {
      cleanPhone = "+90" + cleanPhone.substring(1);
    } else {
      cleanPhone = "+90" + cleanPhone;
    }
  }

  const db = getFirestore();

  // En son gönderilen ve süresi dolmamış OTP'yi bul
  const otpDocs = await db.collection("otp_codes")
      .where("phoneNumber", "==", cleanPhone)
      .where("verified", "==", false)
      .where("expiresAt", ">", new Date())
      .orderBy("expiresAt", "desc")
      .limit(1)
      .get();

  if (otpDocs.empty) {
    return {success: false, error: "Kod süresi dolmuş veya bulunamadı."};
  }

  const otpDoc = otpDocs.docs[0];
  const otpData = otpDoc.data();
  const storedCode = otpData.code;

  // KABA KUVVET KORUMASI: 6 haneli kod, sayaç olmadan sınırsız denenebiliyordu.
  const attempts = (otpData.attempts || 0) + 1;
  const MAX_OTP_ATTEMPTS = 5;
  if (attempts > MAX_OTP_ATTEMPTS) {
    await otpDoc.ref.delete();
    return {success: false, error: "Çok fazla hatalı deneme. Yeni kod isteyin."};
  }

  if (storedCode === otpCode) {
    // Doğrulandı — işaretle
    await otpDoc.ref.update({verified: true, verifiedAt: new Date()});

    // Eski OTP'leri temizle
    // WriteBatch 500 işlemle sınırlıdır; limit olmadan eski kayıtlar
    // biriktiğinde commit tamamen başarısız oluyordu.
    const oldOtps = await db.collection("otp_codes")
        .where("phoneNumber", "==", cleanPhone)
        .where("verified", "==", false)
        .limit(400)
        .get();
    const batch = db.batch();
    oldOtps.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();

    console.log(`✅ OTP doğrulandı: ${cleanPhone}`);
    return {success: true};
  } else {
    await otpDoc.ref.update({attempts: attempts});
    return {success: false, error: "Hatalı doğrulama kodu."};
  }
});

// ============================================================
// Pub/Sub push dogrulama
// ============================================================
/**
 * Google Pub/Sub push aboneliginin OIDC jetonunu dogrular.
 *
 * Abonelik Google Cloud Console > Pub/Sub > Subscriptions > (RTDN aboneligi)
 * > Authentication ile bir hizmet hesabina baglanmalidir. Aksi halde bu
 * fonksiyon her push'i reddeder ve iadeler yalnizca gunluk taramayla islenir.
 */
async function verifyPubSubPush(req) {
  try {
    const header = req.get("Authorization") || "";
    if (!header.startsWith("Bearer ")) return false;

    const token = header.substring(7);
    const {OAuth2Client} = require("google-auth-library");
    const client = new OAuth2Client();

    // Audience, aboneligin push endpoint URL'idir. Bu 2. nesil bir fonksiyon
    // oldugu icin adres cloudfunctions.net degil *.run.app olabilir; sabit
    // kurmak yerine gelen istegin kendi adresinden hesapliyoruz.
    const host = req.get("x-forwarded-host") || req.get("host");
    let audience = `https://${host}${req.path || ""}`;
    if (audience.endsWith("/")) {
      audience = audience.slice(0, -1);
    }

    const ticket = await client.verifyIdToken({idToken: token, audience});
    const payload = ticket.getPayload();
    return !!(payload && payload.iss === "https://accounts.google.com");
  } catch (e) {
    console.error("RTDN dogrulama hatasi:", e.message);
    return false;
  }
}

// ============================================================
// HESAP SİLME — App Store Guideline 5.1.1(v)
// ============================================================
// ESKİ DURUM (istemci tarafındaydı ve çalışmıyordu):
//  - Tek bir WriteBatch kullanılıyordu (500 işlem sınırı). Mesajı çok olan
//    kullanıcıda batch fırlıyor, ATOMİK olduğu için `users/{uid}` dahil
//    HİÇBİR ŞEY silinmiyordu ve `user.delete()` hiç çalışmıyordu.
//  - Dört sorgu var olmayan alan adlarını kullanıyordu:
//      messages.participants (gerçek: senderId/receiverId)
//      likes.from/to        (gerçek: fromUserId/toUserId)
//      reports.reporter/reported (gerçek: reporterId/reportedUserId)
//      blocked_users.blocked → kural zaten reddediyordu
//    Yani özel mesajlar dahil hiçbiri silinmiyordu.
//  - Depolamada `user_photos/{uid}` ÖN EKİ siliniyordu ama yüklemeler
//    `user_photos/{uid}_...` düz dosya adıyla yapılıyor → hiçbir profil
//    fotoğrafı silinmiyordu.
//  - Kullanıcıyı biri engellemişse silme tamamen başarısız oluyordu; yani
//    çıkmak isteyen en kırılgan kullanıcı çıkamıyordu.
//
// Artık sunucuda, parçalı ve sırayla çalışıyor.

/** Bir sorgunun tüm sonuçlarını sayfalayarak siler. */
async function deleteByQuery(db, collection, field, value, label) {
  let removed = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snap = await db.collection(collection)
      .where(field, "==", value)
      .limit(400)
      .get();
    if (snap.empty) break;
    removed += await deleteDocsInChunks(db, snap.docs);
    if (snap.size < 400) break;
  }
  if (removed > 0) console.log(`${label || collection}: ${removed} kayit silindi`);
  return removed;
}

/** Storage'da bir ön ek altındaki her şeyi siler. */
async function deleteStoragePrefix(bucket, prefix) {
  try {
    await bucket.deleteFiles({prefix});
  } catch (e) {
    console.error(`Storage temizligi basarisiz (${prefix}):`, e.message);
  }
}

exports.deleteAccount = onCall(
  {
    region: "us-central1",
    cors: true,
    enforceAppCheck: false,
    timeoutSeconds: 540,
  },
  async (request) => {
    const uid = requireAuth(request);
    const db = getFirestore();

    console.log(`Hesap silme basladi: ${uid}`);

    try {
      // --- 1. Kullanıcıya ait tekil dokümanlar ---
      const singleDocs = [
        "users", "user_stats", "email_verifications",
        "phone_verifications", "password_verifications",
      ];
      for (const coll of singleDocs) {
        try {
          await db.collection(coll).doc(uid).delete();
        } catch (e) {
          console.error(`${coll}/${uid} silinemedi:`, e.message);
        }
      }

      // --- 2. userId alanı taşıyan koleksiyonlar ---
      const byUserId = [
        "check_ins", "check_in_history", "favorite_venue_history",
        "saved_venues", "feed_posts", "notifications", "daily_mayors",
        "diamond_transactions", "legal_acceptances", "mayor_transaction_logs",
      ];
      for (const coll of byUserId) {
        await deleteByQuery(db, coll, "userId", uid);
      }

      // --- 3. İki taraflı ilişkiler ---
      // DOĞRU alan adları — eskiden burası tamamen yanlıştı.
      await deleteByQuery(db, "matches", "user1Id", uid, "matches(user1)");
      await deleteByQuery(db, "matches", "user2Id", uid, "matches(user2)");
      await deleteByQuery(db, "messages", "senderId", uid, "messages(gonderen)");
      await deleteByQuery(db, "messages", "receiverId", uid, "messages(alan)");
      await deleteByQuery(db, "chat_requests", "fromUserId", uid);
      await deleteByQuery(db, "chat_requests", "toUserId", uid);
      await deleteByQuery(db, "blocked_users", "blocker", uid);
      await deleteByQuery(db, "blocked_users", "blocked", uid);

      // --- 4. Alt koleksiyon ---
      try {
        const sub = await db.collection("users").doc(uid)
          .collection("blocked_users").limit(400).get();
        await deleteDocsInChunks(db, sub.docs);
      } catch (e) {
        console.error("blocked_users alt koleksiyonu:", e.message);
      }

      // --- 5. Finansal kayıtlar: SİLİNMEZ, kimliksizleştirilir ---
      // Satın alma ve abonelik kayıtları muhasebe/iade için saklanmalı;
      // ama kişisel veri taşımamalı.
      for (const coll of ["purchases", "premium_subscriptions",
        "restored_purchases"]) {
        try {
          const snap = await db.collection(coll)
            .where("userId", "==", uid).limit(400).get();
          for (let i = 0; i < snap.docs.length; i += 400) {
            const batch = db.batch();
            snap.docs.slice(i, i + 400).forEach((d) => {
              batch.update(d.ref, {
                userId: "deleted_user",
                anonymizedAt: new Date(),
              });
            });
            await batch.commit();
          }
        } catch (e) {
          console.error(`${coll} kimliksizlestirme:`, e.message);
        }
      }

      // --- 6. Şikâyetler: güvenlik kaydı olarak SAKLANIR ---
      // Silinirse, taciz eden kişi hesabını silerek geçmişini temizleyebilirdi.
      // Yalnızca kimliksizleştirme yapılmaz; moderasyon için gerekli.

      // --- 7. Depolama: ÜÇ ayrı yol da temizlenir ---
      const bucket = getStorage().bucket();
      await deleteStoragePrefix(bucket, `users/${uid}/`);
      await deleteStoragePrefix(bucket, `user_photos/${uid}_`);
      // Check-in fotoğrafları: klasör adı `{timestamp}_{uid}` biçiminde,
      // ön ekle bulunamaz; listeleyip eşleşenleri siliyoruz.
      try {
        const [files] = await bucket.getFiles({prefix: "checkins/"});
        const mine = files.filter((f) => f.name.includes(`_${uid}/`));
        await Promise.all(mine.map((f) => f.delete().catch(() => {})));
      } catch (e) {
        console.error("check-in fotograflari:", e.message);
      }

      // --- 8. Auth hesabı ---
      await getAuth().deleteUser(uid);

      console.log(`Hesap silindi: ${uid}`);
      return {success: true};
    } catch (error) {
      console.error("Hesap silme hatasi:", error);
      return {
        success: false,
        error: "Hesap silinemedi. Lütfen tekrar deneyin veya destek ile iletişime geçin.",
      };
    }
  }
);

// ============================================================
// MODERASYON — Apple Guideline 1.2 (UGC)
// ============================================================
// ESKİ DURUM: `reports` koleksiyonu doluyor ama üzerinde işlem yapacak
// HİÇBİR araç yoktu. `ADMIN_REVIEW_READINESS_PLAN.md` setAdminClaim ve
// bootstrapAdminClaim fonksiyonlarının var olduğunu yazıyordu; ikisi de
// kodda yoktu. `user_warnings` koleksiyonunun kuralı vardı, kodu yoktu.
// `ReportService.getUserReportCount()` `status == 'confirmed'` filtreliyordu
// ama hiçbir kod status'ü 'pending' dışına çıkarmıyordu — yani hep 0.
//
// Aşağıdakiler bu boşluğu kapatır. Hepsi admin talebi (custom claim) ister.
// İlk admin, Admin SDK ile elle atanır (bootstrap); sonrakiler buradan.

/** Bir kullanıcıya admin yetkisi verir/alır. Yalnızca mevcut bir admin çağırabilir. */
exports.setAdminClaim = onCall(
  {region: "us-central1", cors: true, enforceAppCheck: false},
  async (request) => {
    requireAdmin(request);

    const {targetUid, isAdmin} = request.data || {};
    if (!targetUid) {
      return {success: false, error: "targetUid gerekli"};
    }

    try {
      await getAuth().setCustomUserClaims(targetUid, {admin: isAdmin === true});
      // Yetki değişikliği hemen geçerli olsun.
      await getAuth().revokeRefreshTokens(targetUid);

      await getFirestore().collection("system_logs").add({
        type: "admin_claim_changed",
        timestamp: new Date(),
        actor: request.auth.uid,
        targetUid: targetUid,
        isAdmin: isAdmin === true,
      });

      return {success: true};
    } catch (error) {
      console.error("setAdminClaim hatasi:", error);
      return {success: false, error: "Yetki guncellenemedi"};
    }
  }
);

/** Kullanıcıyı askıya alır veya askıyı kaldırır. */
exports.banUser = onCall(
  {region: "us-central1", cors: true, enforceAppCheck: false},
  async (request) => {
    requireAdmin(request);

    const {targetUid, banned, reason} = request.data || {};
    if (!targetUid) {
      return {success: false, error: "targetUid gerekli"};
    }

    const db = getFirestore();
    const shouldBan = banned !== false;

    try {
      // Auth tarafında da devre dışı bırak: yalnızca Firestore bayrağı
      // yeterli değil, kullanıcı yine oturum açabilirdi.
      await getAuth().updateUser(targetUid, {disabled: shouldBan});
      if (shouldBan) {
        await getAuth().revokeRefreshTokens(targetUid);
      }

      await db.collection("users").doc(targetUid).set({
        isBanned: shouldBan,
        bannedAt: shouldBan ? new Date() : null,
        banReason: shouldBan ? (reason || "Topluluk kurallari ihlali") : null,
        isActive: !shouldBan,
      }, {merge: true});

      if (shouldBan) {
        await db.collection("user_warnings").add({
          userId: targetUid,
          type: "ban",
          reason: reason || "Topluluk kurallari ihlali",
          actor: request.auth.uid,
          createdAt: new Date(),
        });
      }

      await db.collection("system_logs").add({
        type: shouldBan ? "user_banned" : "user_unbanned",
        timestamp: new Date(),
        actor: request.auth.uid,
        targetUid: targetUid,
      });

      return {success: true};
    } catch (error) {
      console.error("banUser hatasi:", error);
      return {success: false, error: "Islem tamamlanamadi"};
    }
  }
);

/** Bir şikâyeti sonuçlandırır. */
exports.resolveReport = onCall(
  {region: "us-central1", cors: true, enforceAppCheck: false},
  async (request) => {
    requireAdmin(request);

    const {reportId, status, note} = request.data || {};
    const allowed = ["confirmed", "rejected", "reviewing"];
    if (!reportId || !allowed.includes(status)) {
      return {success: false, error: "reportId ve gecerli bir status gerekli"};
    }

    try {
      await getFirestore().collection("reports").doc(reportId).update({
        status: status,
        resolvedAt: new Date(),
        resolvedBy: request.auth.uid,
        resolutionNote: note || null,
      });
      return {success: true};
    } catch (error) {
      console.error("resolveReport hatasi:", error);
      return {success: false, error: "Sikayet guncellenemedi"};
    }
  }
);

/** Admin için bekleyen şikâyet kuyruğu. */
exports.listPendingReports = onCall(
  {region: "us-central1", cors: true, enforceAppCheck: false},
  async (request) => {
    requireAdmin(request);

    try {
      const snap = await getFirestore().collection("reports")
        .where("status", "==", "pending")
        .limit(100)
        .get();

      return {
        success: true,
        reports: snap.docs.map((d) => Object.assign({id: d.id}, d.data())),
      };
    } catch (error) {
      console.error("listPendingReports hatasi:", error);
      return {success: false, error: "Sikayetler getirilemedi"};
    }
  }
);
