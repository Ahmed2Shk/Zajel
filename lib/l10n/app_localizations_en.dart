// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Zajel';

  @override
  String get send => 'Send';

  @override
  String get receive => 'Receive';

  @override
  String get recentTransfers => 'Recent transfers';

  @override
  String get noRecentTransfers => 'No transfers yet';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get showQr => 'Show QR';

  @override
  String get scanQr => 'Scan QR';

  @override
  String get filePickerTitle => 'Choose files';

  @override
  String get tabPhotos => 'Photos';

  @override
  String get tabVideos => 'Videos';

  @override
  String get tabApps => 'Apps';

  @override
  String get tabFiles => 'Files';

  @override
  String sendCount(int count) {
    return 'Send ($count)';
  }

  @override
  String get discoveryTitle => 'Nearby devices';

  @override
  String get qrShowTitle => 'Show QR code';

  @override
  String get qrScanTitle => 'Scan QR code';

  @override
  String get transferTitle => 'Transferring';

  @override
  String get cancel => 'Cancel';

  @override
  String get doneTitle => 'Transfer complete';

  @override
  String get openFiles => 'Open files';

  @override
  String get sendMore => 'Send more';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get deviceName => 'Device name';

  @override
  String get downloadFolder => 'Download folder';

  @override
  String get language => 'Language';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageEnglish => 'English';

  @override
  String get theme => 'Theme';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get themeSystem => 'System';

  @override
  String get securityPin => 'Security PIN';

  @override
  String get device => 'Device';

  @override
  String get unavailable => 'Unavailable';

  @override
  String get searchingDevices => 'Looking for nearby devices…';

  @override
  String get noDevicesFound =>
      'No devices found. Make sure the other device is on the same Wi-Fi with Zajel or LocalSend open.';

  @override
  String get searchAgain => 'Search again';

  @override
  String readyToReceive(String name) {
    return 'Ready to receive as $name';
  }

  @override
  String get chooseFiles => 'Choose files';

  @override
  String get noFilesSelected => 'No files selected yet';

  @override
  String get pickFilesFirst => 'Choose files first';

  @override
  String get incomingTitle => 'Incoming files';

  @override
  String incomingBody(String sender, int count, String size) {
    return '$sender wants to send $count files ($size)';
  }

  @override
  String get accept => 'Accept';

  @override
  String get decline => 'Decline';

  @override
  String get declinedByReceiver => 'The other device declined the request';

  @override
  String get sendFailed => 'Sending failed';

  @override
  String get enterPin => 'Enter PIN';

  @override
  String get pinRequiredHint => 'The other device requires a PIN';

  @override
  String get ok => 'OK';

  @override
  String sendingTo(String name) {
    return 'Sending to $name';
  }

  @override
  String get webShareTitle => 'Share through a browser';

  @override
  String get webShareIntro =>
      'For any device without Zajel: scan the code or open the link in its browser on the same network. It can download the files you chose and send files to this device.';

  @override
  String get webShareWarning =>
      'This page is not encrypted (HTTP). Use it only on a network you trust, and do not send sensitive files.';

  @override
  String get webShareStart => 'Start sharing';

  @override
  String get webShareStop => 'Stop sharing';

  @override
  String get webShareRunning =>
      'Sharing is on. Anyone on the network with this link can open the page.';

  @override
  String webShareFiles(int count) {
    return 'Files available to download: $count';
  }

  @override
  String get webPageTitle => 'Zajel';

  @override
  String get webPageWarning =>
      'This page is not encrypted. Use it on a network you trust only.';

  @override
  String get webPageDownloads => 'Download from this device';

  @override
  String get webPageUploads => 'Send to this device';

  @override
  String get webPageChoose => 'Choose files';

  @override
  String get webPageSend => 'Send';

  @override
  String get webPageWaiting => 'Waiting for the other device to accept…';

  @override
  String get webPageDone => 'Sent';

  @override
  String get webPageDeclined => 'The other device declined the request';

  @override
  String get webPageBusy =>
      'The device is busy with another transfer, try again shortly';

  @override
  String get webPageFailed => 'Sending failed';

  @override
  String get webPagePin => 'Enter PIN';

  @override
  String get webPageNoFiles => 'No files to download';

  @override
  String get defaultValue => 'Default';

  @override
  String get editDeviceName => 'Edit device name';

  @override
  String get save => 'Save';

  @override
  String get chooseFolder => 'Choose folder';

  @override
  String get downloadFolderFixed =>
      'On Android, files are saved in the app\'s folder.';

  @override
  String get pinNotSet => 'No PIN';

  @override
  String get pinDialogHint =>
      '4 to 8 digits. The sending device must enter it before any file is sent.';

  @override
  String get clearPin => 'Remove PIN';

  @override
  String get transferNotification => 'Transferring files…';

  @override
  String get benchmarkTitle => 'Speed test';

  @override
  String get benchmarkIntro =>
      'Sends test data to another Zajel device without saving any file, and measures speed, connection time and CPU use. Works with Zajel only.';

  @override
  String get benchmarkRun => 'Start test';

  @override
  String get benchmarkSize => 'Data size';

  @override
  String get benchmarkConnect => 'Connection time';

  @override
  String get benchmarkCpu => 'CPU';

  @override
  String get benchmarkNoPeer => 'Pick a nearby Zajel device to start';

  @override
  String get benchmarkFailed =>
      'The test failed. Make sure the other device runs Zajel, not another app.';

  @override
  String get benchmarkRunning => 'Testing…';

  @override
  String filesCount(int count) {
    return '$count files';
  }
}
