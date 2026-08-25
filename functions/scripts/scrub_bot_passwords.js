const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

initializeApp();

async function main() {
  const db = getFirestore();
  const snapshot = await db.collection("users")
    .where("isBot", "==", true)
    .get();

  let cleaned = 0;
  const batch = db.batch();

  snapshot.forEach((doc) => {
    const data = doc.data();
    if (Object.prototype.hasOwnProperty.call(data, "botPassword")) {
      batch.update(doc.ref, {
        botPassword: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      cleaned++;
    }
  });

  if (cleaned > 0) {
    await batch.commit();
  }

  console.log(`Bot password fields cleaned: ${cleaned}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
