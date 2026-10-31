// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'زاجل';

  @override
  String get send => 'إرسال';

  @override
  String get receive => 'استقبال';

  @override
  String get recentTransfers => 'آخر عمليات النقل';

  @override
  String get noRecentTransfers => 'لا توجد عمليات نقل بعد';

  @override
  String get comingSoon => 'قريباً';

  @override
  String get showQr => 'عرض QR';

  @override
  String get scanQr => 'مسح QR';

  @override
  String get filePickerTitle => 'اختيار الملفات';

  @override
  String get tabPhotos => 'الصور';

  @override
  String get tabVideos => 'الفيديو';

  @override
  String get tabApps => 'التطبيقات';

  @override
  String get tabFiles => 'الملفات';

  @override
  String sendCount(int count) {
    return 'إرسال ($count)';
  }

  @override
  String get discoveryTitle => 'الأجهزة القريبة';

  @override
  String get qrShowTitle => 'عرض رمز QR';

  @override
  String get qrScanTitle => 'مسح رمز QR';

  @override
  String get transferTitle => 'جاري النقل';

  @override
  String get cancel => 'إلغاء';

  @override
  String get doneTitle => 'تم النقل';

  @override
  String get openFiles => 'فتح الملفات';

  @override
  String get sendMore => 'إرسال المزيد';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get deviceName => 'اسم الجهاز';

  @override
  String get downloadFolder => 'مجلد التنزيل';

  @override
  String get language => 'اللغة';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageEnglish => 'English';

  @override
  String get theme => 'المظهر';

  @override
  String get themeDark => 'داكن';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeSystem => 'حسب النظام';

  @override
  String get securityPin => 'رمز الأمان (PIN)';

  @override
  String get device => 'الجهاز';

  @override
  String get unavailable => 'غير متاح';

  @override
  String get searchingDevices => 'جاري البحث عن أجهزة قريبة…';

  @override
  String get noDevicesFound =>
      'لم يتم العثور على أجهزة. تأكد أن الجهاز الآخر على نفس شبكة الواي فاي ومفتوح عليه زاجل أو LocalSend.';

  @override
  String get searchAgain => 'إعادة البحث';

  @override
  String readyToReceive(String name) {
    return 'جاهز للاستقبال باسم $name';
  }

  @override
  String get chooseFiles => 'اختر ملفات';

  @override
  String get noFilesSelected => 'لم تختر أي ملف بعد';

  @override
  String get pickFilesFirst => 'اختر ملفات أولاً';

  @override
  String get incomingTitle => 'طلب استلام ملفات';

  @override
  String incomingBody(String sender, int count, String size) {
    return '$sender يريد إرسال $count ملف ($size)';
  }

  @override
  String get accept => 'قبول';

  @override
  String get decline => 'رفض';

  @override
  String get declinedByReceiver => 'رفض الجهاز الآخر الطلب';

  @override
  String get sendFailed => 'فشل الإرسال';

  @override
  String get enterPin => 'أدخل رمز PIN';

  @override
  String get pinRequiredHint => 'الجهاز الآخر يطلب رمز PIN';

  @override
  String get ok => 'موافق';

  @override
  String sendingTo(String name) {
    return 'الإرسال إلى $name';
  }

  @override
  String get transferNotification => 'جاري نقل الملفات…';

  @override
  String get benchmarkTitle => 'اختبار السرعة';

  @override
  String get benchmarkIntro =>
      'يرسل بيانات تجريبية إلى جهاز زاجل آخر بدون حفظ أي ملف، ويقيس السرعة وزمن الاتصال واستهلاك المعالج. يعمل مع زاجل فقط.';

  @override
  String get benchmarkRun => 'ابدأ الاختبار';

  @override
  String get benchmarkSize => 'حجم البيانات';

  @override
  String get benchmarkConnect => 'زمن الاتصال';

  @override
  String get benchmarkCpu => 'المعالج';

  @override
  String get benchmarkNoPeer => 'اختر جهاز زاجل قريب لبدء الاختبار';

  @override
  String get benchmarkFailed =>
      'فشل الاختبار. تأكد أن الجهاز الآخر يشغّل زاجل وليس تطبيقاً آخر.';

  @override
  String get benchmarkRunning => 'جاري الاختبار…';

  @override
  String filesCount(int count) {
    return '$count ملف';
  }
}
