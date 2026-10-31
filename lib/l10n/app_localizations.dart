import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appName.
  ///
  /// In ar, this message translates to:
  /// **'زاجل'**
  String get appName;

  /// No description provided for @send.
  ///
  /// In ar, this message translates to:
  /// **'إرسال'**
  String get send;

  /// No description provided for @receive.
  ///
  /// In ar, this message translates to:
  /// **'استقبال'**
  String get receive;

  /// No description provided for @recentTransfers.
  ///
  /// In ar, this message translates to:
  /// **'آخر عمليات النقل'**
  String get recentTransfers;

  /// No description provided for @noRecentTransfers.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد عمليات نقل بعد'**
  String get noRecentTransfers;

  /// No description provided for @comingSoon.
  ///
  /// In ar, this message translates to:
  /// **'قريباً'**
  String get comingSoon;

  /// No description provided for @showQr.
  ///
  /// In ar, this message translates to:
  /// **'عرض QR'**
  String get showQr;

  /// No description provided for @scanQr.
  ///
  /// In ar, this message translates to:
  /// **'مسح QR'**
  String get scanQr;

  /// No description provided for @filePickerTitle.
  ///
  /// In ar, this message translates to:
  /// **'اختيار الملفات'**
  String get filePickerTitle;

  /// No description provided for @tabPhotos.
  ///
  /// In ar, this message translates to:
  /// **'الصور'**
  String get tabPhotos;

  /// No description provided for @tabVideos.
  ///
  /// In ar, this message translates to:
  /// **'الفيديو'**
  String get tabVideos;

  /// No description provided for @tabApps.
  ///
  /// In ar, this message translates to:
  /// **'التطبيقات'**
  String get tabApps;

  /// No description provided for @tabFiles.
  ///
  /// In ar, this message translates to:
  /// **'الملفات'**
  String get tabFiles;

  /// No description provided for @sendCount.
  ///
  /// In ar, this message translates to:
  /// **'إرسال ({count})'**
  String sendCount(int count);

  /// No description provided for @discoveryTitle.
  ///
  /// In ar, this message translates to:
  /// **'الأجهزة القريبة'**
  String get discoveryTitle;

  /// No description provided for @qrShowTitle.
  ///
  /// In ar, this message translates to:
  /// **'عرض رمز QR'**
  String get qrShowTitle;

  /// No description provided for @qrScanTitle.
  ///
  /// In ar, this message translates to:
  /// **'مسح رمز QR'**
  String get qrScanTitle;

  /// No description provided for @transferTitle.
  ///
  /// In ar, this message translates to:
  /// **'جاري النقل'**
  String get transferTitle;

  /// No description provided for @cancel.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء'**
  String get cancel;

  /// No description provided for @doneTitle.
  ///
  /// In ar, this message translates to:
  /// **'تم النقل'**
  String get doneTitle;

  /// No description provided for @openFiles.
  ///
  /// In ar, this message translates to:
  /// **'فتح الملفات'**
  String get openFiles;

  /// No description provided for @sendMore.
  ///
  /// In ar, this message translates to:
  /// **'إرسال المزيد'**
  String get sendMore;

  /// No description provided for @settingsTitle.
  ///
  /// In ar, this message translates to:
  /// **'الإعدادات'**
  String get settingsTitle;

  /// No description provided for @deviceName.
  ///
  /// In ar, this message translates to:
  /// **'اسم الجهاز'**
  String get deviceName;

  /// No description provided for @downloadFolder.
  ///
  /// In ar, this message translates to:
  /// **'مجلد التنزيل'**
  String get downloadFolder;

  /// No description provided for @language.
  ///
  /// In ar, this message translates to:
  /// **'اللغة'**
  String get language;

  /// No description provided for @languageArabic.
  ///
  /// In ar, this message translates to:
  /// **'العربية'**
  String get languageArabic;

  /// No description provided for @languageEnglish.
  ///
  /// In ar, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @theme.
  ///
  /// In ar, this message translates to:
  /// **'المظهر'**
  String get theme;

  /// No description provided for @themeDark.
  ///
  /// In ar, this message translates to:
  /// **'داكن'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In ar, this message translates to:
  /// **'فاتح'**
  String get themeLight;

  /// No description provided for @themeSystem.
  ///
  /// In ar, this message translates to:
  /// **'حسب النظام'**
  String get themeSystem;

  /// No description provided for @securityPin.
  ///
  /// In ar, this message translates to:
  /// **'رمز الأمان (PIN)'**
  String get securityPin;

  /// No description provided for @device.
  ///
  /// In ar, this message translates to:
  /// **'الجهاز'**
  String get device;

  /// No description provided for @unavailable.
  ///
  /// In ar, this message translates to:
  /// **'غير متاح'**
  String get unavailable;

  /// No description provided for @searchingDevices.
  ///
  /// In ar, this message translates to:
  /// **'جاري البحث عن أجهزة قريبة…'**
  String get searchingDevices;

  /// No description provided for @noDevicesFound.
  ///
  /// In ar, this message translates to:
  /// **'لم يتم العثور على أجهزة. تأكد أن الجهاز الآخر على نفس شبكة الواي فاي ومفتوح عليه زاجل أو LocalSend.'**
  String get noDevicesFound;

  /// No description provided for @searchAgain.
  ///
  /// In ar, this message translates to:
  /// **'إعادة البحث'**
  String get searchAgain;

  /// No description provided for @readyToReceive.
  ///
  /// In ar, this message translates to:
  /// **'جاهز للاستقبال باسم {name}'**
  String readyToReceive(String name);

  /// No description provided for @chooseFiles.
  ///
  /// In ar, this message translates to:
  /// **'اختر ملفات'**
  String get chooseFiles;

  /// No description provided for @noFilesSelected.
  ///
  /// In ar, this message translates to:
  /// **'لم تختر أي ملف بعد'**
  String get noFilesSelected;

  /// No description provided for @pickFilesFirst.
  ///
  /// In ar, this message translates to:
  /// **'اختر ملفات أولاً'**
  String get pickFilesFirst;

  /// No description provided for @incomingTitle.
  ///
  /// In ar, this message translates to:
  /// **'طلب استلام ملفات'**
  String get incomingTitle;

  /// No description provided for @incomingBody.
  ///
  /// In ar, this message translates to:
  /// **'{sender} يريد إرسال {count} ملف ({size})'**
  String incomingBody(String sender, int count, String size);

  /// No description provided for @accept.
  ///
  /// In ar, this message translates to:
  /// **'قبول'**
  String get accept;

  /// No description provided for @decline.
  ///
  /// In ar, this message translates to:
  /// **'رفض'**
  String get decline;

  /// No description provided for @declinedByReceiver.
  ///
  /// In ar, this message translates to:
  /// **'رفض الجهاز الآخر الطلب'**
  String get declinedByReceiver;

  /// No description provided for @sendFailed.
  ///
  /// In ar, this message translates to:
  /// **'فشل الإرسال'**
  String get sendFailed;

  /// No description provided for @enterPin.
  ///
  /// In ar, this message translates to:
  /// **'أدخل رمز PIN'**
  String get enterPin;

  /// No description provided for @pinRequiredHint.
  ///
  /// In ar, this message translates to:
  /// **'الجهاز الآخر يطلب رمز PIN'**
  String get pinRequiredHint;

  /// No description provided for @ok.
  ///
  /// In ar, this message translates to:
  /// **'موافق'**
  String get ok;

  /// No description provided for @sendingTo.
  ///
  /// In ar, this message translates to:
  /// **'الإرسال إلى {name}'**
  String sendingTo(String name);

  /// No description provided for @defaultValue.
  ///
  /// In ar, this message translates to:
  /// **'الافتراضي'**
  String get defaultValue;

  /// No description provided for @editDeviceName.
  ///
  /// In ar, this message translates to:
  /// **'تعديل اسم الجهاز'**
  String get editDeviceName;

  /// No description provided for @save.
  ///
  /// In ar, this message translates to:
  /// **'حفظ'**
  String get save;

  /// No description provided for @chooseFolder.
  ///
  /// In ar, this message translates to:
  /// **'اختيار مجلد'**
  String get chooseFolder;

  /// No description provided for @downloadFolderFixed.
  ///
  /// In ar, this message translates to:
  /// **'على أندرويد تُحفظ الملفات في مجلد التطبيق.'**
  String get downloadFolderFixed;

  /// No description provided for @pinNotSet.
  ///
  /// In ar, this message translates to:
  /// **'بدون رمز'**
  String get pinNotSet;

  /// No description provided for @pinDialogHint.
  ///
  /// In ar, this message translates to:
  /// **'من 4 إلى 8 أرقام. يُطلب من الجهاز المرسل قبل إرسال أي ملف.'**
  String get pinDialogHint;

  /// No description provided for @clearPin.
  ///
  /// In ar, this message translates to:
  /// **'إزالة الرمز'**
  String get clearPin;

  /// No description provided for @transferNotification.
  ///
  /// In ar, this message translates to:
  /// **'جاري نقل الملفات…'**
  String get transferNotification;

  /// No description provided for @benchmarkTitle.
  ///
  /// In ar, this message translates to:
  /// **'اختبار السرعة'**
  String get benchmarkTitle;

  /// No description provided for @benchmarkIntro.
  ///
  /// In ar, this message translates to:
  /// **'يرسل بيانات تجريبية إلى جهاز زاجل آخر بدون حفظ أي ملف، ويقيس السرعة وزمن الاتصال واستهلاك المعالج. يعمل مع زاجل فقط.'**
  String get benchmarkIntro;

  /// No description provided for @benchmarkRun.
  ///
  /// In ar, this message translates to:
  /// **'ابدأ الاختبار'**
  String get benchmarkRun;

  /// No description provided for @benchmarkSize.
  ///
  /// In ar, this message translates to:
  /// **'حجم البيانات'**
  String get benchmarkSize;

  /// No description provided for @benchmarkConnect.
  ///
  /// In ar, this message translates to:
  /// **'زمن الاتصال'**
  String get benchmarkConnect;

  /// No description provided for @benchmarkCpu.
  ///
  /// In ar, this message translates to:
  /// **'المعالج'**
  String get benchmarkCpu;

  /// No description provided for @benchmarkNoPeer.
  ///
  /// In ar, this message translates to:
  /// **'اختر جهاز زاجل قريب لبدء الاختبار'**
  String get benchmarkNoPeer;

  /// No description provided for @benchmarkFailed.
  ///
  /// In ar, this message translates to:
  /// **'فشل الاختبار. تأكد أن الجهاز الآخر يشغّل زاجل وليس تطبيقاً آخر.'**
  String get benchmarkFailed;

  /// No description provided for @benchmarkRunning.
  ///
  /// In ar, this message translates to:
  /// **'جاري الاختبار…'**
  String get benchmarkRunning;

  /// No description provided for @filesCount.
  ///
  /// In ar, this message translates to:
  /// **'{count} ملف'**
  String filesCount(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
