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

  /// No description provided for @homeReadyTitle.
  ///
  /// In ar, this message translates to:
  /// **'جاهز للإرسال والاستقبال'**
  String get homeReadyTitle;

  /// No description provided for @homeReadySubtitle.
  ///
  /// In ar, this message translates to:
  /// **'شبكة محلية مباشرة • بدون إنترنت أو إعلانات'**
  String get homeReadySubtitle;

  /// No description provided for @sendSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'صور، فيديو، مستندات وتطبيقات بسرعة عالية'**
  String get sendSubtitle;

  /// No description provided for @receiveSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'استقبال الملفات من الأجهزة القريبة بدون إنترنت'**
  String get receiveSubtitle;

  /// No description provided for @directLink.
  ///
  /// In ar, this message translates to:
  /// **'رابط مباشر'**
  String get directLink;

  /// No description provided for @directLinkSub.
  ///
  /// In ar, this message translates to:
  /// **'مشاركة عبر المتصفح'**
  String get directLinkSub;

  /// No description provided for @qrTile.
  ///
  /// In ar, this message translates to:
  /// **'رمز QR'**
  String get qrTile;

  /// No description provided for @qrTileSub.
  ///
  /// In ar, this message translates to:
  /// **'اتصال سريع'**
  String get qrTileSub;

  /// No description provided for @historyClear.
  ///
  /// In ar, this message translates to:
  /// **'مسح'**
  String get historyClear;

  /// No description provided for @directionSent.
  ///
  /// In ar, this message translates to:
  /// **'أُرسل'**
  String get directionSent;

  /// No description provided for @directionReceived.
  ///
  /// In ar, this message translates to:
  /// **'استُلم'**
  String get directionReceived;

  /// No description provided for @pickPhotos.
  ///
  /// In ar, this message translates to:
  /// **'اختيار صور'**
  String get pickPhotos;

  /// No description provided for @pickVideos.
  ///
  /// In ar, this message translates to:
  /// **'اختيار فيديو'**
  String get pickVideos;

  /// No description provided for @appsLoading.
  ///
  /// In ar, this message translates to:
  /// **'جاري تحميل التطبيقات…'**
  String get appsLoading;

  /// No description provided for @appsNone.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد تطبيقات'**
  String get appsNone;

  /// No description provided for @appsUnsupported.
  ///
  /// In ar, this message translates to:
  /// **'اختيار التطبيقات متاح على أندرويد فقط'**
  String get appsUnsupported;

  /// No description provided for @selectedItems.
  ///
  /// In ar, this message translates to:
  /// **'{count} عناصر محددة'**
  String selectedItems(int count);

  /// No description provided for @readyToSendSize.
  ///
  /// In ar, this message translates to:
  /// **'جاهز للإرسال • {size}'**
  String readyToSendSize(String size);

  /// No description provided for @clearSelection.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء التحديد'**
  String get clearSelection;

  /// No description provided for @searchingNearby.
  ///
  /// In ar, this message translates to:
  /// **'البحث عن أجهزة مجاورة…'**
  String get searchingNearby;

  /// No description provided for @foundCount.
  ///
  /// In ar, this message translates to:
  /// **'تم العثور على {count}'**
  String foundCount(int count);

  /// No description provided for @discoveryTip.
  ///
  /// In ar, this message translates to:
  /// **'تأكد من فتح زاجل على الجهاز الآخر، أو أبقِ على هذه الشاشة للاتصال الفوري بدون إنترنت.'**
  String get discoveryTip;

  /// No description provided for @etaLabel.
  ///
  /// In ar, this message translates to:
  /// **'الوقت المتبقي'**
  String get etaLabel;

  /// No description provided for @transferredSoFar.
  ///
  /// In ar, this message translates to:
  /// **'المنقول حتى الآن'**
  String get transferredSoFar;

  /// No description provided for @overallProgress.
  ///
  /// In ar, this message translates to:
  /// **'التقدم الإجمالي'**
  String get overallProgress;

  /// No description provided for @fileListTitle.
  ///
  /// In ar, this message translates to:
  /// **'قائمة الملفات ({count})'**
  String fileListTitle(int count);

  /// No description provided for @fileDone.
  ///
  /// In ar, this message translates to:
  /// **'تم النقل بنجاح'**
  String get fileDone;

  /// No description provided for @fileWaiting.
  ///
  /// In ar, this message translates to:
  /// **'قيد الانتظار'**
  String get fileWaiting;

  /// No description provided for @fileSending.
  ///
  /// In ar, this message translates to:
  /// **'جاري الإرسال'**
  String get fileSending;

  /// No description provided for @etaSeconds.
  ///
  /// In ar, this message translates to:
  /// **'{s} ث'**
  String etaSeconds(int s);

  /// No description provided for @etaMinutes.
  ///
  /// In ar, this message translates to:
  /// **'{m} د {s} ث'**
  String etaMinutes(int m, int s);

  /// No description provided for @connectedTo.
  ///
  /// In ar, this message translates to:
  /// **'متصل مع الجهاز'**
  String get connectedTo;

  /// No description provided for @webShareTitle.
  ///
  /// In ar, this message translates to:
  /// **'المشاركة عبر المتصفح'**
  String get webShareTitle;

  /// No description provided for @webShareIntro.
  ///
  /// In ar, this message translates to:
  /// **'لجهاز ما عنده زاجل (كمبيوتر، آيفون، تلفاز…). متصفحه يحمّل الملفات مباشرة من هذا الهاتف عبر الواي فاي. لا يمرّ شيء عبر الإنترنت ولا يحتاج اتصالاً بالإنترنت. امسح الرمز أو افتح الرابط من متصفح ذلك الجهاز. ويستطيع أيضاً إرسال ملفات إلى هذا الهاتف.'**
  String get webShareIntro;

  /// No description provided for @webShareWarning.
  ///
  /// In ar, this message translates to:
  /// **'هذه الصفحة غير مشفّرة (HTTP). استخدمها فقط على شبكة تثق بها، ولا ترسل ملفات حساسة.'**
  String get webShareWarning;

  /// No description provided for @webShareStart.
  ///
  /// In ar, this message translates to:
  /// **'تشغيل المشاركة'**
  String get webShareStart;

  /// No description provided for @webShareStop.
  ///
  /// In ar, this message translates to:
  /// **'إيقاف المشاركة'**
  String get webShareStop;

  /// No description provided for @webShareRunning.
  ///
  /// In ar, this message translates to:
  /// **'المشاركة تعمل. أي شخص يملك هذا الرابط على الشبكة يستطيع فتح الصفحة.'**
  String get webShareRunning;

  /// No description provided for @webShareFiles.
  ///
  /// In ar, this message translates to:
  /// **'ملفات متاحة للتنزيل: {count}'**
  String webShareFiles(int count);

  /// No description provided for @webPageTitle.
  ///
  /// In ar, this message translates to:
  /// **'زاجل'**
  String get webPageTitle;

  /// No description provided for @webPageWarning.
  ///
  /// In ar, this message translates to:
  /// **'هذه الصفحة غير مشفّرة. استخدمها على شبكة تثق بها فقط.'**
  String get webPageWarning;

  /// No description provided for @webPageDownloads.
  ///
  /// In ar, this message translates to:
  /// **'تنزيل من هذا الجهاز'**
  String get webPageDownloads;

  /// No description provided for @webPageUploads.
  ///
  /// In ar, this message translates to:
  /// **'إرسال إلى هذا الجهاز'**
  String get webPageUploads;

  /// No description provided for @webPageChoose.
  ///
  /// In ar, this message translates to:
  /// **'اختر ملفات'**
  String get webPageChoose;

  /// No description provided for @webPageSend.
  ///
  /// In ar, this message translates to:
  /// **'إرسال'**
  String get webPageSend;

  /// No description provided for @webPageWaiting.
  ///
  /// In ar, this message translates to:
  /// **'بانتظار موافقة الجهاز الآخر…'**
  String get webPageWaiting;

  /// No description provided for @webPageDone.
  ///
  /// In ar, this message translates to:
  /// **'تم الإرسال'**
  String get webPageDone;

  /// No description provided for @webPageDeclined.
  ///
  /// In ar, this message translates to:
  /// **'رفض الجهاز الآخر الطلب'**
  String get webPageDeclined;

  /// No description provided for @webPageBusy.
  ///
  /// In ar, this message translates to:
  /// **'الجهاز مشغول بنقل آخر، حاول بعد قليل'**
  String get webPageBusy;

  /// No description provided for @webPageFailed.
  ///
  /// In ar, this message translates to:
  /// **'فشل الإرسال'**
  String get webPageFailed;

  /// No description provided for @webPagePin.
  ///
  /// In ar, this message translates to:
  /// **'أدخل رمز PIN'**
  String get webPagePin;

  /// No description provided for @webPageNoFiles.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد ملفات للتنزيل'**
  String get webPageNoFiles;

  /// No description provided for @receivingTitle.
  ///
  /// In ar, this message translates to:
  /// **'جاري الاستقبال'**
  String get receivingTitle;

  /// No description provided for @receivedTitle.
  ///
  /// In ar, this message translates to:
  /// **'تم الاستقبال'**
  String get receivedTitle;

  /// No description provided for @receiveCancelled.
  ///
  /// In ar, this message translates to:
  /// **'أُلغي النقل'**
  String get receiveCancelled;

  /// No description provided for @receivingFrom.
  ///
  /// In ar, this message translates to:
  /// **'من الجهاز'**
  String get receivingFrom;

  /// No description provided for @fileSaving.
  ///
  /// In ar, this message translates to:
  /// **'جاري الحفظ…'**
  String get fileSaving;

  /// No description provided for @fileSaved.
  ///
  /// In ar, this message translates to:
  /// **'تم الحفظ'**
  String get fileSaved;

  /// No description provided for @openFile.
  ///
  /// In ar, this message translates to:
  /// **'فتح'**
  String get openFile;

  /// No description provided for @savedWhere.
  ///
  /// In ar, this message translates to:
  /// **'تُحفظ الصور في Pictures والفيديو في Movies والصوت في Music وباقي الملفات في Download، داخل مجلد Zajel.'**
  String get savedWhere;

  /// No description provided for @savedInAppFolder.
  ///
  /// In ar, this message translates to:
  /// **'حُفظت الملفات في مجلد التطبيق (أندرويد 9 وما قبله).'**
  String get savedInAppFolder;

  /// No description provided for @wifiLine.
  ///
  /// In ar, this message translates to:
  /// **'الواي فاي: {info}'**
  String wifiLine(String info);

  /// No description provided for @slowLinkHint.
  ///
  /// In ar, this message translates to:
  /// **'السرعة منخفضة. غالباً الراوتر يحدّ سرعة كل جهاز أو يمرّر النقل عبره. جرّب رمز QR أو Wi-Fi Direct للاتصال المباشر بين الجهازين.'**
  String get slowLinkHint;

  /// No description provided for @deviceGone.
  ///
  /// In ar, this message translates to:
  /// **'هذا الجهاز لم يعد متاحاً. ابحث من جديد.'**
  String get deviceGone;

  /// No description provided for @joinManually.
  ///
  /// In ar, this message translates to:
  /// **'الانضمام يدوياً'**
  String get joinManually;

  /// No description provided for @joinManuallyIntro.
  ///
  /// In ar, this message translates to:
  /// **'افتح إعدادات الواي فاي واتصل بهذه الشبكة، ثم ارجع واضغط «اتصلت».'**
  String get joinManuallyIntro;

  /// No description provided for @joinPassword.
  ///
  /// In ar, this message translates to:
  /// **'كلمة السر'**
  String get joinPassword;

  /// No description provided for @joinConnected.
  ///
  /// In ar, this message translates to:
  /// **'اتصلت'**
  String get joinConnected;

  /// No description provided for @copy.
  ///
  /// In ar, this message translates to:
  /// **'نسخ'**
  String get copy;

  /// No description provided for @mediaDenied.
  ///
  /// In ar, this message translates to:
  /// **'نحتاج إذن الوصول إلى الصور والفيديو لعرضها هنا.'**
  String get mediaDenied;

  /// No description provided for @mediaAllow.
  ///
  /// In ar, this message translates to:
  /// **'السماح بالوصول'**
  String get mediaAllow;

  /// No description provided for @mediaOpenSettings.
  ///
  /// In ar, this message translates to:
  /// **'فتح الإعدادات'**
  String get mediaOpenSettings;

  /// No description provided for @mediaLimited.
  ///
  /// In ar, this message translates to:
  /// **'سمحت بجزء من الصور فقط. يمكنك تغيير ذلك من الإعدادات.'**
  String get mediaLimited;

  /// No description provided for @mediaEmpty.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد عناصر'**
  String get mediaEmpty;

  /// No description provided for @mediaUnsupported.
  ///
  /// In ar, this message translates to:
  /// **'عرض الصور والفيديو متاح على أندرويد وآيفون فقط. استخدم تبويب الملفات.'**
  String get mediaUnsupported;

  /// No description provided for @mediaUnreadable.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر قراءة هذا الملف'**
  String get mediaUnreadable;

  /// No description provided for @filesAndroidNote.
  ///
  /// In ar, this message translates to:
  /// **'لا يسمح أندرويد للتطبيقات بعرض كل الملفات تلقائياً. اختر الملفات من مدير الملفات.'**
  String get filesAndroidNote;

  /// No description provided for @reviewSelection.
  ///
  /// In ar, this message translates to:
  /// **'مراجعة المحدد'**
  String get reviewSelection;

  /// No description provided for @qrShowIntro.
  ///
  /// In ar, this message translates to:
  /// **'اطلب من الجهاز الآخر مسح هذا الرمز. سيتصل بهذا الجهاز مباشرة بدون إنترنت أو راوتر.'**
  String get qrShowIntro;

  /// No description provided for @qrPinLabel.
  ///
  /// In ar, this message translates to:
  /// **'رمز PIN'**
  String get qrPinLabel;

  /// No description provided for @qrNetworkLabel.
  ///
  /// In ar, this message translates to:
  /// **'الشبكة'**
  String get qrNetworkLabel;

  /// No description provided for @qrStarting.
  ///
  /// In ar, this message translates to:
  /// **'جاري تجهيز الاتصال…'**
  String get qrStarting;

  /// No description provided for @qrScanHint.
  ///
  /// In ar, this message translates to:
  /// **'وجّه الكاميرا نحو رمز QR المعروض على الجهاز الآخر'**
  String get qrScanHint;

  /// No description provided for @qrInvalid.
  ///
  /// In ar, this message translates to:
  /// **'هذا الرمز ليس رمز زاجل'**
  String get qrInvalid;

  /// No description provided for @qrConnecting.
  ///
  /// In ar, this message translates to:
  /// **'جاري الاتصال بالجهاز…'**
  String get qrConnecting;

  /// No description provided for @cameraDenied.
  ///
  /// In ar, this message translates to:
  /// **'تم رفض إذن الكاميرا. اسمح بالوصول إلى الكاميرا لمسح الرمز.'**
  String get cameraDenied;

  /// No description provided for @retry.
  ///
  /// In ar, this message translates to:
  /// **'إعادة المحاولة'**
  String get retry;

  /// No description provided for @tfPermission.
  ///
  /// In ar, this message translates to:
  /// **'اسمح بإذن «الأجهزة القريبة» (أو «الموقع» على أندرويد 12 وما قبله) ثم أعد المحاولة.'**
  String get tfPermission;

  /// No description provided for @tfLocation.
  ///
  /// In ar, this message translates to:
  /// **'شغّل خدمة الموقع في الجهاز، فهي مطلوبة على أندرويد 12 وما قبله.'**
  String get tfLocation;

  /// No description provided for @tfWifi.
  ///
  /// In ar, this message translates to:
  /// **'شغّل الواي فاي (لا يلزم الاتصال بشبكة).'**
  String get tfWifi;

  /// No description provided for @tfUnsupported.
  ///
  /// In ar, this message translates to:
  /// **'هذا الجهاز لا يدعم هذه الميزة.'**
  String get tfUnsupported;

  /// No description provided for @tfBusy.
  ///
  /// In ar, this message translates to:
  /// **'الواي فاي مشغول. أوقف نقطة الاتصال الخاصة بالجوال أو أي اتصال Wi-Fi Direct ثم حاول مجدداً.'**
  String get tfBusy;

  /// No description provided for @tfTimeout.
  ///
  /// In ar, this message translates to:
  /// **'انتهت مهلة الاتصال. قرّب الجهازين من بعض وحاول مرة أخرى.'**
  String get tfTimeout;

  /// No description provided for @tfFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر إنشاء الاتصال.'**
  String get tfFailed;

  /// No description provided for @suggestQr.
  ///
  /// In ar, this message translates to:
  /// **'لم نجد أجهزة. جرّب رمز QR للاتصال بدون راوتر.'**
  String get suggestQr;

  /// No description provided for @wifiDirect.
  ///
  /// In ar, this message translates to:
  /// **'Wi-Fi Direct'**
  String get wifiDirect;

  /// No description provided for @directSearch.
  ///
  /// In ar, this message translates to:
  /// **'البحث عبر Wi-Fi Direct'**
  String get directSearch;

  /// No description provided for @directVisible.
  ///
  /// In ar, this message translates to:
  /// **'إظهار هذا الجهاز عبر Wi-Fi Direct'**
  String get directVisible;

  /// No description provided for @directVisibleOn.
  ///
  /// In ar, this message translates to:
  /// **'هذا الجهاز ظاهر عبر Wi-Fi Direct'**
  String get directVisibleOn;

  /// No description provided for @directStop.
  ///
  /// In ar, this message translates to:
  /// **'إيقاف الظهور'**
  String get directStop;

  /// No description provided for @directBadge.
  ///
  /// In ar, this message translates to:
  /// **'مباشر'**
  String get directBadge;

  /// No description provided for @directNone.
  ///
  /// In ar, this message translates to:
  /// **'لم يُعثر على أجهزة عبر Wi-Fi Direct'**
  String get directNone;

  /// No description provided for @exportLogs.
  ///
  /// In ar, this message translates to:
  /// **'تصدير السجل'**
  String get exportLogs;

  /// No description provided for @exportLogsSub.
  ///
  /// In ar, this message translates to:
  /// **'ملف نصي محلي بدون أسماء ملفات أو رموز أو بيانات شخصية. يُحفظ حيث تختار.'**
  String get exportLogsSub;

  /// No description provided for @clearLogs.
  ///
  /// In ar, this message translates to:
  /// **'مسح السجل'**
  String get clearLogs;

  /// No description provided for @logsSaved.
  ///
  /// In ar, this message translates to:
  /// **'تم حفظ السجل'**
  String get logsSaved;

  /// No description provided for @logsEmpty.
  ///
  /// In ar, this message translates to:
  /// **'السجل فارغ'**
  String get logsEmpty;

  /// No description provided for @logsExportFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر حفظ السجل'**
  String get logsExportFailed;

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
