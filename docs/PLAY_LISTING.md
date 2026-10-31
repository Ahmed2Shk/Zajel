# Google Play listing (draft)

Fill the placeholders marked `TODO`. Screenshots come from the finished UI, in Arabic and English.

**Only claim what the manual tests confirmed.** Statements about speed, screen-off transfers and
LocalSend compatibility below are goals until `docs/TESTING.md` is ticked on real phones.

## App name

Zajel — زاجل (30 characters max)

## Short description (80 characters max)

- English: `Send files to nearby devices fast. No internet, no ads, no account.` (68)
- العربية: `أرسل الملفات للأجهزة القريبة بسرعة. بدون إنترنت أو إعلانات أو حساب.` (66)

## Full description

### English

Zajel moves photos, videos, documents and apps between nearby devices, quickly and privately.

- **No internet needed.** Works on the same Wi-Fi, over a hotspot you create with a QR code, or Wi-Fi Direct.
- **No ads, no account, no tracking.** The app has no servers at all.
- **Private.** Every transfer is encrypted and the receiver must accept it. Optional PIN.
- **Fast.** Big files are sent in parallel pieces, and they carry on with the screen off.
- **Works with LocalSend.** Send to and receive from the official LocalSend apps on phones and computers.
- **Any device.** A browser page lets a device without the app download or upload files.
- **Arabic and English**, made for right-to-left reading.

Speed depends on both devices' Wi-Fi hardware. Newer phones on 5 GHz are fastest. (Add measured speeds only after
testing on real phones, from `docs/BENCHMARKS.md`.)

### العربية

زاجل ينقل الصور والفيديو والمستندات والتطبيقات بين الأجهزة القريبة بسرعة وخصوصية.

- **بدون إنترنت.** يعمل على نفس شبكة الواي فاي، أو عبر نقطة اتصال تنشئها برمز QR، أو عبر Wi-Fi Direct.
- **بدون إعلانات أو حساب أو تتبّع.** التطبيق لا يستخدم أي خادم.
- **خاص.** كل عملية نقل مشفّرة ويجب أن يوافق المستلم عليها. ورمز PIN اختياري.
- **سريع.** الملفات الكبيرة تُرسل على أجزاء متوازية وتستمر والشاشة مطفأة.
- **متوافق مع LocalSend.** أرسل واستقبل مع تطبيقات LocalSend الرسمية على الجوال والكمبيوتر.
- **لأي جهاز.** صفحة متصفح تتيح لجهاز بدون التطبيق تنزيل الملفات أو رفعها.
- **عربي وإنجليزي** وبواجهة تدعم القراءة من اليمين لليسار.

## Data safety form

| Question | Answer |
| --- | --- |
| Does the app collect or share user data? | No |
| Is data encrypted in transit? | Yes (TLS between devices). The optional browser page uses HTTP and says so. |
| Can users request data deletion? | There is no data off the device. Clearing history or uninstalling removes everything. |
| Ads | None |

## Declarations to answer in Play Console

- **Foreground service type:** data sync (keeps a transfer running with the screen off).
- **Permissions:** nearby devices / location (hotspot and Wi-Fi Direct), camera (QR), notifications.
- **Photos and videos permission** (`READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`): Play restricts these to apps whose
  core feature needs persistent access to the media library. Zajel's picker shows a thumbnail grid of the user's
  photos and videos for file transfer; be ready to explain that in the declaration, or switch to the system
  Photo Picker if Google asks for it. The app does not request all-files access.
- **Package visibility:** uses a `<queries>` launcher intent to list launchable apps. It does **not** use
  QUERY_ALL_PACKAGES.
- **Target audience:** all ages. **Content rating:** complete the questionnaire. No user-generated content.
- **Privacy policy URL:** host `docs/PRIVACY_POLICY.md` publicly and paste the URL. TODO.

## Assets to prepare (TODO)

- App icon 512×512, feature graphic 1024×500.
- Phone screenshots (home, picker, discovery, progress, QR, settings) in both languages.
- Contact email and website.
