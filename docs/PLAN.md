# خطة زاجل (Zajel)

تطبيق نقل ملفات أوفلاين، بدون إعلانات، أسرع وأبسط من SHAREit، ومتوافق مع بروتوكول LocalSend v2.1. مبني بـ Flutter، والأجزاء الحساسة للسرعة native بـ Kotlin.

ملفات مرتبطة: `SPEC.md` (المتطلبات وشروط القبول)، `PROMPTS.md` (البرومتات)، `TESTING.md` (قائمة الاختبار)، `design/README.md` (الهوية البصرية).

## المعمارية

التطبيق بيجرّب طرق الاتصال من الأسرع للأضمن، وبيتوقف عند أول وحدة بتنجح.

| الأولوية | الطريقة | المنصات | ملاحظات |
| --- | --- | --- | --- |
| 1 | Wi-Fi Direct | Android ↔ Android | تلقائي، بدون راوتر |
| 2 | LocalOnlyHotspot + QR | أندرويد ينشئ، أي جهاز يتصل | أضمن طريق، ونفسه للآيفون |
| 3 | نفس شبكة الواي فاي | الكل | اكتشاف UDP multicast على 224.0.0.167 |
| 4 | متصفح ويب | أي جهاز فيه متصفح | سيرفر HTTP صغير على الجوال + QR |
| لاحقاً | Wi-Fi Aware | Android ↔ iPhone 12+ على iOS 26 | تجريبي، المرحلة 6 |

طبقات الكود:

1. **Discovery:** UDP multicast + mDNS بالتوازي.
2. **Transport Manager:** بيختار أسرع طريقة متاحة، وبيرجع للي بعدها تلقائياً.
3. **Transfer Engine:** بروتوكول LocalSend v2، مع chunks واستئناف واتصالات متوازية.
4. **Security:** TLS بشهادة self-signed، والتحقق بالـ fingerprint أو PIN أو QR.
5. **UI:** Flutter.

مسار البيانات على أندرويد (الاستقبال والكتابة على القرص) native بـ Kotlin، والتواصل مع Flutter عبر Pigeon.

## أسرار السرعة

- اتصالات متوازية: chunks حجمها 4–8 MB على 3–4 اتصالات TCP.
- كتابة native مباشرة على القرص بدون نسخ عبر Dart.
- تردد 5 GHz كل ما أمكن.
- بدون ضغط للصور والفيديو، لأنها مضغوطة أصلاً.
- الملفات الصغيرة الكثيرة بتنبعت كـ tar stream واحد.
- WifiLock + WakeLock + foreground service عشان النقل ما يبطّئ لما الشاشة تطفي.
- benchmark ثابت (ملف 1 GB) لقياس كل تحسين.

## هل رح يزبط؟

سرعة وضع التيربو بتاع SHAREit ممكن توصلها، بس «100% على كل جهاز» مش ممكنة لأي تطبيق.

| المقارنة | السرعة |
| --- | --- |
| SHAREit (ادعاء تسويقي) | حتى 42 MB/s |
| LocalSend، لابتوب ↔ لابتوب | 41–42 MB/s |
| LocalSend، ماك ↔ أندرويد | 24–28 MB/s |
| LocalSend، تقارير مستخدمين | 8–20 MB/s |

- **الهدف الواقعي:** 20–40 MB/s بين جوالات 5 GHz حديثة، ونجاح 95% أو أكثر.
- **السقف:** بيحدده أضعف جهاز من الاثنين، يعني شريحة الواي فاي وسرعة الذاكرة.
- **ليش مش 100%:** الآيفون ما بيقدر يعمل Hotspot برمجياً، وأندرويد 10+ بيطلب تأكيد، وبعض الشركات بتقتل التطبيقات بالخلفية، والأجهزة القديمة بطيئة.

## خطة المراحل

| المرحلة | الهدف | شرط الانتقال |
| --- | --- | --- |
| 0. التأسيس | هيكل المشروع، الثيم، الشاشات الفاضية | بيشتغل على جوال أندرويد |
| 1. المحرك الأساسي | بروتوكول LocalSend على نفس الشبكة مع TLS | نقل 1 GB مع LocalSend الرسمي |
| 2. السرعة | مسار native، توازي، استئناف، benchmark | 20–40 MB/s |
| 3. بدون راوتر | QR + Hotspot، و Wi-Fi Direct | نقل بدون أي شبكة |
| 4. الكمبيوتر والمتصفح | ويندوز وماك ولينكس والمتصفح | نقل أندرويد ↔ كمبيوتر ↔ متصفح |
| 5. إطلاق الأندرويد | واجهة نهائية، أمان، Google Play | 10 مختبرين على 6 ماركات |
| 6. الآيفون (آخر شي) | QR + Hotspot، و Wi-Fi Aware تجريبي، Codemagic | نقل أندرويد ↔ آيفون |

## الأدوات

- Android Studio مع إضافة Flutter، و Claude Code من التيرمنال، و Git + GitHub.
- جوالين أندرويد حقيقيين (واحد على الأقل 5 GHz)، و scrcpy، و adb.
- تطبيق LocalSend الرسمي لاختبار التوافق، و iperf3 لقياس سقف الواي فاي.
- الآيفون بالمرحلة 6 بس: Codemagic + TestFlight + حساب مطوّر آبل.

## المراجع

| المرجع | ليش |
| --- | --- |
| [LocalSend Protocol](https://github.com/localsend/protocol) | البروتوكول اللي رح نتوافق معه |
| [localsend/localsend](https://github.com/localsend/localsend) | تطبيق Flutter كامل بنفس الفكرة |
| [localsend-rs](https://github.com/CrossCopy/localsend-rs) | تنفيذ مرتب للبروتوكول |
| [google/nearby](https://github.com/google/nearby) | كيف Google بتعمل ترقية الاتصال |
| [NearDrop](https://github.com/grishka/NearDrop) | توثيق بروتوكول Quick Share |
| [Apple Wi-Fi Aware](https://developer.apple.com/documentation/wifiaware/building-peer-to-peer-apps) | للمرحلة 6 |

## دروس من SHAREit

- كان فيه ثغرات بسبب FileProvider مضبوط غلط، وما كان بيجبر HTTPS.
- عندنا: TLS دايماً، بدون FileProvider مكشوف، وتنظيف أسماء الملفات المستلمة.
