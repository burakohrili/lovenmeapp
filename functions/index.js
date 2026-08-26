const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onCall, onRequest} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {getAuth} = require("firebase-admin/auth");
const {Resend} = require("resend");
const {defineString, defineSecret} = require("firebase-functions/params");
const functions = require("firebase-functions");
const axios = require("axios");
const cors = require("cors")({origin: true});
const {GoogleAuth} = require("google-auth-library");

initializeApp();

// Parametreleri tanımla
const resendKey = defineString("RESEND_KEY");
const googleServiceAccountKey = defineSecret("GOOGLE_SERVICE_ACCOUNT_KEY");
const netgsmUsercode = defineString("NETGSM_USERCODE");
const netgsmPassword = defineString("NETGSM_PASSWORD");
const netgsmHeader = defineString("NETGSM_HEADER");

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
    const {email, code, userName} = request.data;
    
    console.log(`📧 Email gönderiliyor: ${email}, Kod: ${code}`);
    
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
      console.log("� Kullanıcı limitlerini resetleniyor...");
      const usersSnapshot = await db.collection("users")
        .where("isActive", "==", true)
        .get();
      
      const batch = db.batch();
      let batchCount = 0;
      
      for (const userDoc of usersSnapshot.docs) {
        const userData = userDoc.data();
        const isPremium = userData.isPremium || false;
        
        // Premium süresini kontrol et
        if (isPremium && userData.premiumUntil) {
          const premiumUntil = userData.premiumUntil.toDate();
          if (now > premiumUntil) {
            // Premium süresi dolmuş, normal kullanıcı yap
            batch.update(userDoc.ref, {
              isPremium: false,
              premiumUntil: null,
              premiumType: null,
              dailyChatRequestsRemaining: 5, // 💬 Normal: 5 chat/gün
              dailyRewindsRemaining: 0,
              // superChatsRemaining: unchanged - IAP paketler korunur! 🔥
              lastDailyReset: now,
            });
            console.log(`🔚 Premium süresi doldu: ${userDoc.id} - Normal limitlere döndü (5 chat/gün)`);
          } else {
            // Premium aktif - Sınırsız chat + 3 rewind
            batch.update(userDoc.ref, {
              dailyChatRequestsRemaining: 999, // 💬 Premium: Sınırsız chat
              dailyRewindsRemaining: 3, // 🔄 Günde 3 geri alma hakkı
              // superChatsRemaining: unchanged - IAP paketler korunur! 🔥
              lastDailyReset: now,
            });
            
            console.log(`🔄 Premium reset: ${userDoc.id} - günlük faydalar yenilendi (unlimited chats + 3 rewinds)`);
          }
        } else {
          // Normal kullanıcı limitlerini ayarla
          batch.update(userDoc.ref, {
            dailyChatRequestsRemaining: 5, // 💬 Normal: 5 chat/gün
            dailyRewindsRemaining: 0,
            // superChatsRemaining: unchanged - IAP paketler korunur! 🔥
            lastDailyReset: now,
          });
        }
        
        batchCount++;
        totalProcessed++;
        
        // Her 500 işlemde batch commit et
        if (batchCount === 500) {
          await batch.commit();
          console.log(`✅ ${batchCount} kullanıcı limiti resetlendi`);
          batchCount = 0;
        }
      }
      
      // Kalan batch'i commit et
      if (batchCount > 0) {
        await batch.commit();
        console.log(`✅ Son ${batchCount} kullanıcı limiti resetlendi`);
      }
      
      // 2. GÜNLÜK MUHTAR VERİLERİNİ TEMİZLE
      console.log("👑 Dünkü muhtarlar temizleniyor...");
      const mayorSnapshot = await db.collection("daily_mayors")
        .where("date", "<", today)
        .get();
      
      const mayorBatch = db.batch();
      for (const mayorDoc of mayorSnapshot.docs) {
        mayorBatch.delete(mayorDoc.ref);
      }
      
      if (mayorSnapshot.docs.length > 0) {
        await mayorBatch.commit();
        console.log(`✅ ${mayorSnapshot.docs.length} eski muhtar kaydı temizlendi`);
      }
      
      // 3. ESKİ CHECK-IN'LERİ TEMİZLE (3 günden eski olanları sil - database temizliği için)
      console.log("🧹 3 günden eski check-in'ler temizleniyor...");
      console.log("ℹ️ Açıklama: Sadece 3 günden eski check-in kayıtları database'den silinir");
      console.log("ℹ️ Bu günlük check-in temizliğiyle alakası yok, sadece database temizliği");
      
      const threeDaysAgo = new Date(today.getTime() - 3 * 24 * 60 * 60 * 1000);
      console.log(`📅 3 gün öncesi tarihi: ${threeDaysAgo.toISOString()}`);
      
      const oldCheckInsSnapshot = await db.collection("check_ins")
        .where("checkInTime", "<", threeDaysAgo)
        .limit(1000) // Batch limiti
        .get();
      
      const checkInBatch = db.batch();
      for (const checkInDoc of oldCheckInsSnapshot.docs) {
        checkInBatch.delete(checkInDoc.ref);
      }
      
      if (oldCheckInsSnapshot.docs.length > 0) {
        await checkInBatch.commit();
        console.log(`✅ Database temizliği: ${oldCheckInsSnapshot.docs.length} eski check-in kaydı silindi`);
      } else {
        console.log(`ℹ️ Database temizliği: Silinecek eski check-in bulunamadı`);
      }
      
      // 4. ESKİ CHECK-IN HISTORY'LERİ TEMİZLE (30 günden eski - discover için saklanan)
      console.log("🗃️ 30 günden eski check-in history'ler temizleniyor...");
      const thirtyDaysAgo = new Date(today.getTime() - 30 * 24 * 60 * 60 * 1000);
      console.log(`📅 30 gün öncesi tarihi: ${thirtyDaysAgo.toISOString()}`);
      
      const oldHistorySnapshot = await db.collection("check_in_history")
        .where("expiresAt", "<=", now)
        .limit(1000)
        .get();
      
      const historyBatch = db.batch();
      for (const historyDoc of oldHistorySnapshot.docs) {
        historyBatch.delete(historyDoc.ref);
      }
      
      let historyCleared = 0;
      if (oldHistorySnapshot.docs.length > 0) {
        await historyBatch.commit();
        historyCleared = oldHistorySnapshot.docs.length;
        console.log(`✅ Check-in history temizliği: ${historyCleared} eski discover kaydı silindi`);
      } else {
        console.log(`ℹ️ Check-in history temizliği: Silinecek eski kayıt bulunamadı`);
      }
      
      // 5. FAVORİ VENUE HISTORY TEMİZLİĞİ (Sadece permanent olmayanları temizle)
      console.log("💖 Geçici favori venue history'ler kontrol ediliyor...");
      console.log("ℹ️ NOT: Permanent favori kayıtlar temizlenmez (register favorileri)");
      
      const tempFavoriteSnapshot = await db.collection("favorite_venue_history")
        .where("isPermanent", "!=", true)
        .where("registrationDate", "<", thirtyDaysAgo)
        .limit(1000)
        .get();
      
      const favoriteBatch = db.batch();
      for (const favoriteDoc of tempFavoriteSnapshot.docs) {
        favoriteBatch.delete(favoriteDoc.ref);
      }
      
      let favoritesCleared = 0;
      if (tempFavoriteSnapshot.docs.length > 0) {
        await favoriteBatch.commit();
        favoritesCleared = tempFavoriteSnapshot.docs.length;
        console.log(`✅ Geçici favori history temizliği: ${favoritesCleared} kayıt silindi`);
      } else {
        console.log(`ℹ️ Geçici favori history: Silinecek kayıt bulunamadı`);
      }
      
            // 6. ESKİ BİLDİRİMLERİ TEMİZLE (7 günden eski)
      console.log("📱 Eski bildirimler temizleniyor...");
      const sevenDaysAgo = new Date(today.getTime() - 7 * 24 * 60 * 60 * 1000);
      const oldNotificationsSnapshot = await db.collection("notifications")
        .where("createdAt", "<", sevenDaysAgo)
        .limit(1000)
        .get();
      
      const notificationBatch = db.batch();
      for (const notificationDoc of oldNotificationsSnapshot.docs) {
        notificationBatch.delete(notificationDoc.ref);
      }
      
      if (oldNotificationsSnapshot.docs.length > 0) {
        await notificationBatch.commit();
        console.log(`✅ ${oldNotificationsSnapshot.docs.length} eski bildirim temizlendi`);
      }
      
      // 7. SİSTEM LOG'U KAYDET
      await db.collection("system_logs").add({
        type: "daily_reset",
        timestamp: now,
        usersProcessed: totalProcessed,
        mayorsCleared: mayorSnapshot.docs.length,
        checkInsCleared: oldCheckInsSnapshot.docs.length,
        historyCleared: historyCleared,
        favoritesCleared: favoritesCleared,
        notificationsCleared: oldNotificationsSnapshot.docs.length,
        errors: errors,
        success: true,
      });
      
      // 8. PREMIUM KUYRUK YÖNETİMİ - Süresi dolmuş premiuma sahip kullanıcılar için kuyruktan sonraki premium'ı aktif et
      console.log("🎫 Premium kuyruk kontrolü başlatılıyor...");
      await activateQueuedPremiums(db, now);
      
      console.log("✅ Günlük reset tamamlandı:");
      console.log(`   👥 ${totalProcessed} kullanıcının günlük hakları resetlendi (00:00 otomatik)`);
      console.log(`   👑 ${mayorSnapshot.docs.length} eski muhtar kaydı temizlendi`);
      console.log(`   🗑️ ${oldCheckInsSnapshot.docs.length} eski check-in kaydı silindi (database temizliği)`);
      console.log(`   📋 ${historyCleared} eski check-in history silindi`);
      console.log(`   💖 ${favoritesCleared} geçici favori history silindi`);
      console.log(`   🔔 ${oldNotificationsSnapshot.docs.length} eski bildirim silindi`);
      console.log("ℹ️ NOT: Günlük check-in temizliği ayrı fonksiyonda (venue kapanış saatlerine göre)");
      console.log("ℹ️ NOT: Permanent favori kayıtlar korunur (register favorileri)");
      
      // 6. SİSTEM LOG'U KAYDET
      await db.collection("system_logs").add({
        type: "daily_reset",
        timestamp: now,
        usersProcessed: totalProcessed,
        mayorsCleared: mayorSnapshot.docs.length,
        checkInsCleared: oldCheckInsSnapshot.docs.length,
        notificationsCleared: oldNotificationsSnapshot.docs.length,
        errors: errors,
        success: true,
      });
      
      console.log("✅ Günlük reset tamamlandı:");
      console.log(`   👥 ${totalProcessed} kullanıcının günlük hakları resetlendi (00:00 otomatik)`);
      console.log(`   👑 ${mayorSnapshot.docs.length} eski muhtar kaydı temizlendi`);
      console.log(`   �️ ${oldCheckInsSnapshot.docs.length} eski check-in kaydı silindi (database temizliği)`);
      console.log(`   🔔 ${oldNotificationsSnapshot.docs.length} eski bildirim silindi`);
      console.log("ℹ️ NOT: Günlük check-in temizliği ayrı fonksiyonda (venue kapanış saatlerine göre)");
      
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
      .limit(1000)
      .get();
    
    for (const doc of oldNotificationsSnapshot.docs) {
      await doc.ref.delete();
      totalDeleted++;
    }
    console.log(`🔔 ${oldNotificationsSnapshot.size} eski bildirim temizlendi`);
    
    // 2. Eski notification_requests temizle (1 hafta)
    const oldRequestsSnapshot = await db.collection("notification_requests")
      .where("createdAt", "<", oneWeekAgo)
      .limit(1000)
      .get();
    
    for (const doc of oldRequestsSnapshot.docs) {
      await doc.ref.delete();
      totalDeleted++;
    }
    console.log(`📤 ${oldRequestsSnapshot.size} eski bildirim isteği temizlendi`);
    
    // 3. Eski system_logs temizle (1 ay)
    const oldLogsSnapshot = await db.collection("system_logs")
      .where("timestamp", "<", oneMonthAgo)
      .limit(1000)
      .get();
    
    for (const doc of oldLogsSnapshot.docs) {
      await doc.ref.delete();
      totalDeleted++;
    }
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
}, async () => {
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
      let totalCleaned = 0;
      let venuesProcessed = 0;
      
      // Aktif venue'ları al
      const venuesSnapshot = await db.collection("venues")
        .get();
      
      for (const venueDoc of venuesSnapshot.docs) {
        const venueData = venueDoc.data();
        const venueId = venueDoc.id;
        const venueName = venueData.name || "Bilinmeyen Mekan";
        
        // Kapanış saatini belirle
        let shouldCleanup = false;
        let cleanupReason = "";
        
        if (venueData.closingTime) {
          // Venue'nin kendi kapanış saati var
          const closingTime = venueData.closingTime;
          const timeParts = closingTime.split(":");
          const closingHour = timeParts.length > 0 ? (parseInt(timeParts[0]) || 2) : 2;
          const closingMinute = timeParts.length > 1 ? (parseInt(timeParts[1]) || 0) : 0;
          
          let venueClosingDateTime;
          if (closingHour < 6) {
            // Gece 06:00'dan önce kapanan mekanlar ertesi gün kapanıyor
            const tomorrow = new Date(now);
            tomorrow.setDate(tomorrow.getDate() + 1);
            venueClosingDateTime = new Date(tomorrow.getFullYear(), tomorrow.getMonth(), tomorrow.getDate(), closingHour, closingMinute);
          } else {
            // Normal kapanış saatleri
            venueClosingDateTime = new Date(now.getFullYear(), now.getMonth(), now.getDate(), closingHour, closingMinute);
          }
          
          if (now >= venueClosingDateTime) {
            shouldCleanup = true;
            cleanupReason = `Venue kapanış saati: ${closingTime}`;
          }
        } else {
          // Kapanış saati yok, gece 02:00'da temizle
          const defaultCleanupTime = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 2, 0); // 02:00
          if (now >= defaultCleanupTime) {
            shouldCleanup = true;
            cleanupReason = "Varsayılan kapanış: 02:00";
          }
        }
        
        if (shouldCleanup) {
          const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
          const todayEnd = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
          
          // Bugünkü check-in'leri bul
          const checkInsToDelete = await db.collection("check_ins")
            .where("venueId", "==", venueId)
            .where("checkInTime", ">=", todayStart)
            .where("checkInTime", "<", todayEnd)
            .get();
          
          if (checkInsToDelete.docs.length > 0) {
            // 🔄 YENİ: Check-in'leri silmeden önce history'e kopyala
            const historyBatch = db.batch();
            for (const checkInDoc of checkInsToDelete.docs) {
              const checkInData = checkInDoc.data();
              
              // Check-in history'e ekle (Discover sistemi için 30 gün saklansın)
              const historyDoc = db.collection("check_in_history").doc();
              historyBatch.set(historyDoc, {
                ...checkInData,
                originalCheckInId: checkInDoc.id,
                movedToHistoryAt: now,
                // 30 gün sonra expire olacak
                expiresAt: new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000),
                forDiscoverMatching: true,
              });
            }
            await historyBatch.commit();
            
            // Şimdi güncel check-in'leri sil
            const deleteBatch = db.batch();
            for (const checkInDoc of checkInsToDelete.docs) {
              deleteBatch.delete(checkInDoc.ref);
            }
            await deleteBatch.commit();
            
            totalCleaned += checkInsToDelete.docs.length;
            console.log(`✅ ${venueName}: ${checkInsToDelete.docs.length} check-in temizlendi ve history'e taşındı (${cleanupReason})`);
            
            // Günlük muhtarı da temizle
            const todayKey = `${now.getFullYear()}-${(now.getMonth() + 1).toString().padStart(2, "0")}-${now.getDate().toString().padStart(2, "0")}`;
            const mayorDocId = `${venueId}_${todayKey}`;
            
            try {
              await db.collection("daily_mayors").doc(mayorDocId).delete();
              console.log(`👑 ${venueName}: Günlük muhtar temizlendi`);
            } catch (mayorError) {
              // Muhtar zaten yoksa hata verme
            }
          }
        }
        
        venuesProcessed++;
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
    const {newEmail, code, userName} = request.data;
    
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
    const {email, code, userName} = request.data;
    
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

// PASSWORD RESET EMAIL - ŞİFRE SIFIRLAMA EMAIL'İ
exports.sendPasswordResetEmail = onCall(
  {
    region: "us-central1",
    cors: true,
    enforceAppCheck: false,
  },
  async (request) => {
    const {email, code, userName} = request.data;
    
    console.log(`🔐 Şifre sıfırlama kodu gönderiliyor: ${email}, Kod: ${code}`);
    
    // Input validation
    if (!email || !code) {
      console.error("Email ve kod gerekli");
      return {success: false, error: "Email ve kod gerekli"};
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
        subject: "🔒 LoveNMe - Şifre Sıfırlama Kodu",
        html: `
          <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <div style="background: linear-gradient(135deg, #E91E63 0%, #AD1457 100%); padding: 40px; text-align: center; border-radius: 10px 10px 0 0;">
              <h1 style="color: white; margin: 0; font-size: 28px;">LoveNMe</h1>
              <p style="color: rgba(255,255,255,0.9); margin-top: 10px;">Şifre Sıfırlama</p>
            </div>
            <div style="background: white; padding: 40px; border: 1px solid #e0e0e0; border-radius: 0 0 10px 10px;">
              <h2 style="color: #333; margin-top: 0;">Merhaba${userName ? ` ${userName}` : ''}!</h2>
              <p style="color: #666; font-size: 16px;">Şifrenizi sıfırlamak için aşağıdaki doğrulama kodunu kullanın:</p>
              <div style="background: linear-gradient(135deg, #E91E63 0%, #AD1457 100%); padding: 25px; text-align: center; margin: 30px 0; border-radius: 8px;">
                <span style="font-size: 42px; font-weight: bold; color: white; letter-spacing: 8px; font-family: monospace;">
                  ${code}
                </span>
              </div>
              <div style="background: #fff3cd; border: 1px solid #ffeaa7; padding: 15px; border-radius: 8px; margin: 20px 0;">
                <p style="color: #856404; margin: 0; font-size: 14px;">
                  <strong>⚠️ Güvenlik Uyarısı:</strong><br>
                  • Bu kodu sadece LoveNMe uygulamasında kullanın<br>
                  • Kodu kimseyle paylaşmayın<br>
                  • Şüpheli aktivite fark ederseniz derhal şifrenizi değiştirin
                </p>
              </div>
              <p style="color: #999; font-size: 14px; margin-top: 30px;">
                ⏱️ Bu kod 5 dakika geçerlidir.<br>
                🔒 Kod doğrulandıktan sonra yeni şifrenizi belirleyebilirsiniz.
              </p>
              <hr style="border: none; border-top: 1px solid #e0e0e0; margin: 30px 0;">
              <p style="color: #999; font-size: 12px;">
                Bu şifre sıfırlama işlemini siz başlatmadıysanız, bu emaili görmezden gelebilirsiniz.<br>
                Hesabınızın güvenliğinden endişe ediyorsanız, lütfen bizimle iletişime geçin.
              </p>
            </div>
            <div style="text-align: center; padding: 20px; color: #999; font-size: 12px;">
              © 2026 LoveNMe. Tüm hakları saklıdır.<br>
              <a href="https://lovenme.app" style="color: #E91E63; text-decoration: none;">lovenme.app</a>
            </div>
          </div>
        `,
      });
      
      if (error) {
        console.error("Resend hatası:", error);
        return {success: false, error: error.message};
      }
      
      console.log(`✅ Şifre sıfırlama kodu gönderildi: ${data.id}`);
      return {success: true, messageId: data.id};
    } catch (error) {
      console.error("Email gönderim hatası:", error);
      return {success: false, error: "Email gönderilemedi"};
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
    const {email, newPassword, verificationCode} = request.data;
    
    console.log(`🔐 Şifre sıfırlama isteği: ${email}`);
    
    // Input validation
    if (!email || !newPassword || !verificationCode) {
      console.error("Email, yeni şifre ve doğrulama kodu gerekli");
      return {success: false, error: "Email, yeni şifre ve doğrulama kodu gerekli"};
    }
    
    // Password validation
    if (newPassword.length < 6) {
      return {success: false, error: "Şifre en az 6 karakter olmalı"};
    }
    
    try {
      // Doğrulama kodunu kontrol et
      const codeDoc = await getFirestore()
        .collection("password_reset_codes")
        .doc(email)
        .get();
      
      if (!codeDoc.exists) {
        console.error("Doğrulama kodu bulunamadı");
        return {success: false, error: "Doğrulama kodu bulunamadı"};
      }
      
      const codeData = codeDoc.data();
      
      // Kodun süresini kontrol et
      if (Date.now() > codeData.expiresAt) {
        console.error("Doğrulama kodunun süresi dolmuş");
        return {success: false, error: "Doğrulama kodunun süresi dolmuş"};
      }
      
      // Kodu doğrula
      if (codeData.code !== verificationCode) {
        console.error("Geçersiz doğrulama kodu");
        return {success: false, error: "Geçersiz doğrulama kodu"};
      }
      
      // Kullanıcıyı email ile bul
      const userRecord = await getAuth().getUserByEmail(email);
      
      if (!userRecord) {
        console.error("Kullanıcı bulunamadı");
        return {success: false, error: "Kullanıcı bulunamadı"};
      }
      
      // Şifreyi güncelle
      await getAuth().updateUser(userRecord.uid, {
        password: newPassword,
      });
      
      // Doğrulama kodunu sil
      await getFirestore()
        .collection("password_reset_codes")
        .doc(email)
        .delete();
      
      console.log(`✅ Şifre başarıyla güncellendi: ${email}`);
      return {success: true, message: "Şifre başarıyla güncellendi"};
    } catch (error) {
      console.error("Şifre güncelleme hatası:", error);
      return {success: false, error: error.message || "Şifre güncellenemedi"};
    }
  }
);

// 🗺️ GOOGLE PLACES API PROXY - Bot Manager için (CORS bypass)
exports.searchPlaces = onCall(
  {
    region: "us-central1",
    cors: true,
    enforceAppCheck: false,
  },
  async (request) => {
    const {query, location, radius, type} = request.data;
    
    console.log(`🔍 Google Places arama: "${query}"`);
    
    if (!query || query.trim().length < 3) {
      return {success: false, error: "Arama sorgusu en az 3 karakter olmalı"};
    }
    
    // Firebase Functions v2 için environment variable kullan
    const apiKey = process.env.GOOGLE_PLACES_API_KEY;
    
    if (!apiKey) {
      console.error("Google Places API Key tanımlanmamış");
      return {success: false, error: "Google Places API yapılandırılmamış"};
    }
    
    try {
      // Text Search API kullan
      const response = await axios.get(
        "https://maps.googleapis.com/maps/api/place/textsearch/json",
        {
          params: {
            query: query,
            key: apiKey,
            language: "tr",
            ...(location && {location: location}), // "lat,lng" formatında
            ...(radius && {radius: radius}),
            ...(type && {type: type}),
          },
        }
      );
      
      if (response.data.status !== "OK" && response.data.status !== "ZERO_RESULTS") {
        console.error("Google Places API hatası:", response.data.status);
        return {
          success: false,
          error: `Google Places API hatası: ${response.data.status}`,
        };
      }
      
      console.log(`✅ ${response.data.results.length} sonuç bulundu`);
      
      return {
        success: true,
        results: response.data.results,
        status: response.data.status,
      };
      
    } catch (error) {
      console.error("Google Places arama hatası:", error.message);
      return {
        success: false,
        error: error.message || "Mekan araması başarısız",
      };
    }
  }
);

// 📍 GOOGLE PLACES DETAILS PROXY - Place ID ile detay getir (HTTP endpoint)
exports.getPlaceDetails = onRequest(
  {
    region: "us-central1",
  },
  async (req, res) => {
    return cors(req, res, async () => {
      try {
        const placeId = req.method === 'GET' ? req.query.placeId : req.body.placeId;
        console.log('📍 Place detay getiriliyor:', placeId);

        if (!placeId) {
          res.status(400).json({ success: false, error: 'Place ID gerekli' });
          return;
        }

        // Firebase Functions v2 için environment variable kullan
        const apiKey = process.env.GOOGLE_PLACES_API_KEY;
        if (!apiKey) {
          console.error('Google Places API Key tanımlanmamış');
          res.status(500).json({ success: false, error: 'Google Places API yapılandırılmamış' });
          return;
        }

        const response = await axios.get('https://maps.googleapis.com/maps/api/place/details/json', {
          params: {
            place_id: placeId,
            key: apiKey,
            language: 'tr',
            fields: 'name,formatted_address,geometry,rating,types,vicinity,opening_hours',
          },
        });

        if (response.data.status !== 'OK') {
          console.error('Google Places API hatası:', response.data.status);
          res.status(502).json({ success: false, error: `Google Places API hatası: ${response.data.status}` });
          return;
        }

        console.log('✅ Place detayı alındı:', response.data.result.name);
        res.status(200).json({ success: true, result: response.data.result, status: response.data.status });
      } catch (error) {
        console.error('Place detay hatası:', error && error.message ? error.message : error);
        res.status(500).json({ success: false, error: error.message || 'Place detayı alınamadı' });
      }
    });
  }
);




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
  const storedCode = otpDoc.data().code;

  if (storedCode === otpCode) {
    // Doğrulandı — işaretle
    await otpDoc.ref.update({verified: true, verifiedAt: new Date()});

    // Eski OTP'leri temizle
    const oldOtps = await db.collection("otp_codes")
        .where("phoneNumber", "==", cleanPhone)
        .where("verified", "==", false)
        .get();
    const batch = db.batch();
    oldOtps.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();

    console.log(`✅ OTP doğrulandı: ${cleanPhone}`);
    return {success: true};
  } else {
    return {success: false, error: "Hatalı doğrulama kodu."};
  }
});
