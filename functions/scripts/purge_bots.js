/**
 * Bot hesaplarını kalıcı olarak temizler.
 *
 * Bot altyapısı (createBotAccount, botSendMessage, botPerformCheckIn, ...)
 * functions/index.js'ten kaldırıldı. Bu script, geriye kalan bot VERİSİNİ siler:
 *   - Firestore users/{uid} (isBot == true)
 *   - Firestore user_stats/{uid}
 *   - Firebase Auth hesabı
 *
 * VARSAYILAN: kuru çalışma (dry-run) — hiçbir şey silinmez, sadece rapor verir.
 * Gerçekten silmek için:  node purge_bots.js --confirm
 */

const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");

initializeApp();

const CONFIRM = process.argv.includes("--confirm");

async function main() {
  const db = getFirestore();
  const snapshot = await db.collection("users").where("isBot", "==", true).get();

  if (snapshot.empty) {
    console.log("Bot bulunamadı. Temiz.");
    return;
  }

  console.log(`${snapshot.size} bot bulundu:`);
  snapshot.forEach((doc) => {
    const d = doc.data();
    console.log(`  - ${doc.id}  ${d.email || "(email yok)"}  ${d.fullName || ""}`);
  });

  if (!CONFIRM) {
    console.log("\nKURU ÇALIŞMA — hiçbir şey silinmedi.");
    console.log("Silmek için: node purge_bots.js --confirm");
    return;
  }

  let deleted = 0;
  let authFailed = 0;

  for (const doc of snapshot.docs) {
    const uid = doc.id;

    // Auth hesabı (yoksa sorun değil, devam et)
    try {
      await getAuth().deleteUser(uid);
    } catch (error) {
      authFailed++;
      console.warn(`  Auth silinemedi (${uid}): ${error.message}`);
    }

    await db.collection("user_stats").doc(uid).delete().catch(() => {});
    await doc.ref.delete();
    deleted++;
  }

  console.log(`\nSilinen bot: ${deleted}`);
  if (authFailed > 0) {
    console.log(`Auth kaydı bulunamayan: ${authFailed} (Firestore kaydı yine de silindi)`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
