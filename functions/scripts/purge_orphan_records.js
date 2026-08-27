/**
 * Silinmiş kullanıcılara ait sahipsiz kayıtları temizler.
 *
 * Bot altyapısı kaldırılırken bot kullanıcıları silindi, ancak botların
 * gönderdiği mesaj/istek kayıtları Firestore'da kaldı. Sonuç: uygulamada
 * okunmamış rozeti sayı gösteriyor ama liste boş görünüyor (gönderen
 * profili bulunamadığı için satır çizilemiyor).
 *
 * Bu script şunları tarar ve referans verdiği kullanıcı ARTIK YOKSA siler:
 *   - messages       (senderId / receiverId)
 *   - chat_requests  (fromUserId / toUserId)
 *   - matches        (users dizisi)
 *
 * VARSAYILAN: kuru çalışma — hiçbir şey silinmez, sadece rapor verir.
 * Silmek için:  node purge_orphan_records.js --confirm
 */

const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

// Cloud Shell'de proje kimligi ortamdan otomatik gelmeyebiliyor; acikca veriyoruz.
initializeApp({projectId: process.env.GOOGLE_CLOUD_PROJECT || "lovenme-c1c2f"});

const CONFIRM = process.argv.includes("--confirm");
const db = getFirestore();

// Var olan kullanıcı id'lerini bir kez okuyup bellekte tutuyoruz
async function loadExistingUserIds() {
  const snap = await db.collection("users").get();
  const ids = new Set();
  snap.forEach((d) => ids.add(d.id));
  return ids;
}

function collectIds(data, fields) {
  const out = [];
  for (const f of fields) {
    const v = data[f];
    if (typeof v === "string" && v) out.push(v);
    if (Array.isArray(v)) v.forEach((x) => typeof x === "string" && out.push(x));
  }
  return out;
}

async function scan(collection, fields, existing) {
  const snap = await db.collection(collection).get();
  const orphans = [];
  snap.forEach((doc) => {
    const ids = collectIds(doc.data(), fields);
    // Referans verilen kullanıcılardan en az biri yoksa kayıt sahipsizdir
    const missing = ids.filter((id) => !existing.has(id));
    if (ids.length > 0 && missing.length > 0) {
      orphans.push({ref: doc.ref, id: doc.id, missing});
    }
  });
  return {total: snap.size, orphans};
}

async function deleteAll(refs) {
  // Firestore batch limiti 500
  for (let i = 0; i < refs.length; i += 400) {
    const batch = db.batch();
    refs.slice(i, i + 400).forEach((r) => batch.delete(r));
    await batch.commit();
  }
}

async function main() {
  const existing = await loadExistingUserIds();
  console.log(`Mevcut kullanici sayisi: ${existing.size}\n`);

  const targets = [
    ["messages", ["senderId", "receiverId"]],
    ["chat_requests", ["fromUserId", "toUserId"]],
    ["matches", ["users", "user1Id", "user2Id"]],
  ];

  let grandTotal = 0;
  const allRefs = [];

  for (const [coll, fields] of targets) {
    const {total, orphans} = await scan(coll, fields, existing);
    console.log(`${coll}: ${total} kayit, ${orphans.length} sahipsiz`);
    orphans.slice(0, 10).forEach((o) => {
      console.log(`   - ${o.id}  (eksik kullanici: ${o.missing.join(", ")})`);
    });
    if (orphans.length > 10) {
      console.log(`   ... ve ${orphans.length - 10} kayit daha`);
    }
    grandTotal += orphans.length;
    orphans.forEach((o) => allRefs.push(o.ref));
  }

  if (grandTotal === 0) {
    console.log("\nSahipsiz kayit yok. Temiz.");
    return;
  }

  if (!CONFIRM) {
    console.log(`\nKURU CALISMA - toplam ${grandTotal} sahipsiz kayit bulundu, hicbiri silinmedi.`);
    console.log("Silmek icin: node purge_orphan_records.js --confirm");
    return;
  }

  await deleteAll(allRefs);
  console.log(`\nSilinen sahipsiz kayit: ${grandTotal}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
