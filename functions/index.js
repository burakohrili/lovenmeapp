const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onCall} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {Resend} = require("resend");
const {defineString} = require("firebase-functions/params");
const functions = require("firebase-functions");

initializeApp();

// Parametreyi tanımla
const resendKey = defineString("RESEND_KEY");

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
              © 2025 LoveNMe. Tüm hakları saklıdır.<br>
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
              © 2025 LoveNMe. Tüm hakları saklıdır.<br>
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
              © 2025 LoveNMe. Tüm hakları saklıdır.<br>
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
              © 2025 LoveNMe. Tüm hakları saklıdır.<br>
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