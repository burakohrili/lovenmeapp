# Lovenme Release Signing Reset Plan

## Current Diagnosis

- The previous Google Play upload keystore was not found locally.
- Candidate keystores found in other projects do not match the Lovenme upload certificate shown in Play Console.
- Play Console current upload key SHA-256:
  `A6:EA:AE:C2:99:AA:09:56:0E:88:C7:70:2D:81:7C:F5:02:46:00:EF:B8:4F:6D:87:1F:E2:E7:63:60:30:79:76`
- A new Lovenme upload keystore and PEM certificate have been created locally.

## Local Files Created

- `android/app/lovenme-upload-keystore.jks`
  - Private upload keystore.
  - Keep this file private.
  - Upload it only to Codemagic code signing identities.
- `android/app/lovenme-upload-certificate.pem`
  - Public certificate for Google Play upload key reset.
  - Upload this file to Play Console reset form.
- `android/app/key.properties`
  - Local signing passwords and alias.
  - Keep this file private.

These files are ignored by Git and must not be committed.

## Google Play Reset Steps

Status: submitted on 2026-08-24. Google confirmed the reset request by email.

New upload key active from:

- `2026-08-26 09:47 UTC`
- `2026-08-26 12:47 TRT`

Submitted values:

- Reason: `Yükleme anahtarımı kaybettim`
- Uploaded certificate:
   `android/app/lovenme-upload-certificate.pem`

Next step: wait until Google approves the new upload certificate.

Do not upload a new AAB/APK before the active time above. Google Play will reject uploads until the new upload key becomes valid.

## Codemagic Setup After Google Approves Reset

1. In Codemagic, open personal account `Applications`.
2. Add repository: `github.com/burakohrili/lovenmeapp`.
3. Add Android code signing identity with reference name:
   `lovenme_upload_key`
4. Upload:
   `android/app/lovenme-upload-keystore.jks`
5. Use values from:
   `android/app/key.properties`
6. Create environment variable group:
   `lovenme_android`
7. Add variable:
   `ANDROID_GOOGLE_SERVICES_JSON`
   - Value must be the base64 content of `android/app/google-services.json`.
8. Run workflow:
   `Android release AAB`

## Store Upload Order

1. Google approves upload key reset.
2. Codemagic builds signed AAB.
3. Upload signed AAB to Google Play internal/production track.
4. Verify Play Billing warning is resolved.
5. Continue iOS separately only after correct iOS Firebase config is added.
