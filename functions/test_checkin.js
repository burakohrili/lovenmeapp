/**
 * Check-in API Test Script
 * Firestore check-in operasyonlarını test eder
 * Çalıştır: node test_checkin.js
 */

const { initializeApp, cert, getApps } = require('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');

// Admin SDK ile başlat (service account gerekmez, emülatör kullanır veya default credentials)
if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();

// ---- TEST PARAMETRELERİ ----
// Gerçek bir userId gir (Firebase Auth'dan bir kullanıcının UID'si)
const TEST_USER_ID = 'TEST_USER_UID_BURAYA_YAZ';
const TEST_VENUE_ID = 'test_venue_123';
const TEST_VENUE_NAME = 'Test Mekan';

async function runTests() {
  console.log('\n🧪 Check-in API Testleri Başlıyor...\n');
  let passed = 0;
  let failed = 0;

  // TEST 1: check_ins koleksiyonuna yazma
  console.log('1️⃣  check_ins koleksiyonuna yazma testi...');
  let testDocId;
  try {
    const docRef = await db.collection('check_ins').add({
      userId: TEST_USER_ID,
      venueId: TEST_VENUE_ID,
      venueName: TEST_VENUE_NAME,
      checkInTime: FieldValue.serverTimestamp(),
      latitude: 41.0082,
      longitude: 28.9784,
      fromFavorite: false,
      hasPhoto: false,
      isInitialRegistration: false,
      _testDoc: true,
    });
    testDocId = docRef.id;
    console.log(`   ✅ BAŞARILI - Doc ID: ${docRef.id}`);
    passed++;
  } catch (e) {
    console.log(`   ❌ BAŞARISIZ - Hata: ${e.message}`);
    failed++;
  }

  // TEST 2: check_ins sorgusu (cooldown kontrolü gibi)
  console.log('\n2️⃣  check_ins cooldown sorgusu testi (userId + orderBy checkInTime)...');
  try {
    const result = await db.collection('check_ins')
      .where('userId', '==', TEST_USER_ID)
      .orderBy('checkInTime', 'desc')
      .limit(10)
      .get();
    console.log(`   ✅ BAŞARILI - ${result.docs.length} kayıt bulundu`);
    passed++;
  } catch (e) {
    console.log(`   ❌ BAŞARISIZ - Hata: ${e.message}`);
    if (e.message.includes('index')) {
      console.log('   ⚠️  Firestore INDEX eksik! firestore.indexes.json dosyasını deploy etmen gerekiyor.');
    }
    failed++;
  }

  // TEST 3: Günlük tekrar kontrolü sorgusu
  console.log('\n3️⃣  Günlük tekrar kontrolü sorgusu testi (userId + venueId + checkInTime range)...');
  try {
    const today = new Date();
    const todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate());
    const todayEnd = new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);

    const result = await db.collection('check_ins')
      .where('userId', '==', TEST_USER_ID)
      .where('venueId', '==', TEST_VENUE_ID)
      .where('checkInTime', '>', Timestamp.fromDate(todayStart))
      .where('checkInTime', '<', Timestamp.fromDate(todayEnd))
      .limit(1)
      .get();
    console.log(`   ✅ BAŞARILI - ${result.docs.length} kayıt bulundu`);
    passed++;
  } catch (e) {
    console.log(`   ❌ BAŞARISIZ - Hata: ${e.message}`);
    if (e.message.includes('index')) {
      console.log('   ⚠️  Firestore INDEX eksik!');
    }
    failed++;
  }

  // TEST 4: check_in_history koleksiyonuna yazma
  console.log('\n4️⃣  check_in_history koleksiyonuna yazma testi...');
  try {
    const docRef = await db.collection('check_in_history').add({
      userId: TEST_USER_ID,
      venueId: TEST_VENUE_ID,
      venueName: TEST_VENUE_NAME,
      checkInTime: FieldValue.serverTimestamp(),
      forDiscoverMatching: true,
      expiresAt: Timestamp.fromDate(new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)),
      _testDoc: true,
    });
    console.log(`   ✅ BAŞARILI - Doc ID: ${docRef.id}`);
    passed++;
    // Test dokümanını temizle
    await docRef.delete();
  } catch (e) {
    console.log(`   ❌ BAŞARISIZ - Hata: ${e.message}`);
    failed++;
  }

  // TEST 5: users koleksiyonunu güncelleme
  console.log('\n5️⃣  users koleksiyonu güncelleme testi (totalCheckIns increment)...');
  try {
    // Önce kullanıcı dokümanı var mı kontrol et
    const userDoc = await db.collection('users').doc(TEST_USER_ID).get();
    if (!userDoc.exists) {
      console.log(`   ⚠️  SKIP - TEST_USER_ID (${TEST_USER_ID}) bulunamadı, gerçek bir UID gir`);
    } else {
      await db.collection('users').doc(TEST_USER_ID).update({
        totalCheckIns: FieldValue.increment(0), // 0 ekle, sadece test
        lastCheckInDate: FieldValue.serverTimestamp(),
      });
      console.log(`   ✅ BAŞARILI`);
      passed++;
    }
  } catch (e) {
    console.log(`   ❌ BAŞARISIZ - Hata: ${e.message}`);
    failed++;
  }

  // TEST 6: daily_mayors koleksiyonu
  console.log('\n6️⃣  daily_mayors koleksiyonu testi...');
  try {
    const today = new Date();
    const todayKey = today.toISOString().split('T')[0];
    const mayorDocId = `${TEST_VENUE_ID}_${todayKey}`;

    const mayorDoc = await db.collection('daily_mayors').doc(mayorDocId).get();
    console.log(`   ✅ BAŞARILI - Doküman ${mayorDoc.exists ? 'mevcut' : 'yok'}`);
    passed++;
  } catch (e) {
    console.log(`   ❌ BAŞARISIZ - Hata: ${e.message}`);
    failed++;
  }

  // TEST 7: Test dokümanlarını temizle
  if (testDocId) {
    try {
      await db.collection('check_ins').doc(testDocId).delete();
      console.log('\n🧹 Test dokümanları temizlendi');
    } catch (e) {
      console.log('\n⚠️  Test dokümanı silinemedi (manuel sil):', testDocId);
    }
  }

  // SONUÇ
  console.log('\n' + '='.repeat(50));
  console.log(`📊 SONUÇ: ${passed} başarılı, ${failed} başarısız`);

  if (failed === 0) {
    console.log('✅ Tüm Firestore işlemleri çalışıyor - sorun istemci tarafında');
    console.log('   → Muhtemelen: 5m mesafe limiti veya ProGuard sorunu');
  } else {
    console.log('❌ Firestore sorunu var - yukarıdaki hataları incele');
    console.log('   → Muhtemelen: index eksik veya rules sorunu');
  }
  console.log('='.repeat(50) + '\n');
}

runTests().catch(console.error);
