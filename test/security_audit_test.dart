import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Automated checks for the hard rules in CLAUDE.md. They read the project's
/// own files, so a change that breaks a rule fails the build.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final dartFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.contains('l10n'))
      .toList();

  String stripComments(String source) => source
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  group('Android manifest', () {
    test('cleartext traffic is off', () {
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
    });

    test('there is no FileProvider and no URI permission grants', () {
      expect(manifest.toLowerCase(), isNot(contains('fileprovider')));
      expect(manifest, isNot(contains('grantUriPermissions')));
    });

    test('only the launcher activity is exported', () {
      final exported = RegExp(r'android:exported="true"').allMatches(manifest);
      expect(exported, hasLength(1));
      final activity = RegExp(r'<activity[\s\S]*?</activity>').firstMatch(manifest)!.group(0)!;
      expect(activity, contains('android:exported="true"'));
      expect(activity, contains('android.intent.category.LAUNCHER'));
    });

    test('the transfer service is private', () {
      final service = RegExp(r'<service[\s\S]*?/>').firstMatch(manifest)!.group(0)!;
      expect(service, contains('android:exported="false"'));
    });

    test('only the permissions the app needs are requested', () {
      final requested = RegExp(r'<uses-permission[^>]*android:name="([^"]+)"')
          .allMatches(manifest)
          .map((m) => m.group(1)!)
          .toSet();
      const allowed = {
        'android.permission.INTERNET',
        'android.permission.ACCESS_WIFI_STATE',
        'android.permission.CHANGE_WIFI_MULTICAST_STATE',
        'android.permission.FOREGROUND_SERVICE',
        'android.permission.FOREGROUND_SERVICE_DATA_SYNC',
        'android.permission.WAKE_LOCK',
        'android.permission.POST_NOTIFICATIONS',
        // QR pairing, hotspot and Wi-Fi Direct (phase 3).
        'android.permission.CAMERA',
        'android.permission.CHANGE_WIFI_STATE',
        'android.permission.ACCESS_NETWORK_STATE',
        'android.permission.CHANGE_NETWORK_STATE',
        'android.permission.ACCESS_FINE_LOCATION',
        'android.permission.NEARBY_WIFI_DEVICES',
      };
      expect(requested.difference(allowed), isEmpty,
          reason: 'unexpected permissions: ${requested.difference(allowed)}');
    });

    test('no broad storage, contacts, phone or package-listing permissions', () {
      for (final forbidden in [
        'READ_EXTERNAL_STORAGE',
        'WRITE_EXTERNAL_STORAGE',
        'MANAGE_EXTERNAL_STORAGE',
        'QUERY_ALL_PACKAGES',
        'READ_CONTACTS',
        'READ_PHONE_STATE',
        'RECORD_AUDIO',
        'READ_SMS',
        'ACCESS_BACKGROUND_LOCATION',
      ]) {
        // Only real <uses-permission> tags count; comments may name them.
        expect(
          RegExp('<uses-permission[^>]*$forbidden').hasMatch(manifest),
          isFalse,
          reason: forbidden,
        );
      }
    });

    test('Android 8 (API 26) is the minimum', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('minSdk = 26'));
    });
  });

  group('no ads, analytics or servers', () {
    test('no tracking, ads or crash-reporting packages', () {
      for (final banned in [
        'firebase',
        'google_mobile_ads',
        'admob',
        'sentry',
        'mlkit',
        'ml_kit',
        'mobile_scanner',
        'crashlytics',
        'mixpanel',
        'amplitude',
        'segment',
        'appsflyer',
        'adjust',
        'facebook',
        'posthog',
        'google_analytics',
        'datadog',
        'bugsnag',
        'onesignal',
      ]) {
        expect(pubspec.toLowerCase(), isNot(contains(banned)), reason: banned);
      }
    });

    test('the code contains no URLs of outside servers', () {
      final offenders = <String>[];
      for (final file in dartFiles) {
        final code = stripComments(file.readAsStringSync());
        for (final match in RegExp(r'''https?://[^\s'")]+''').allMatches(code)) {
          offenders.add('${file.path}: ${match.group(0)}');
        }
      }
      expect(offenders, isEmpty);
    });

    test('there is no web or analytics SDK in the Android build', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle.toLowerCase(), isNot(contains('firebase')));
      expect(gradle.toLowerCase(), isNot(contains('google-services')));
    });
  });

  group('plugins pull in no telemetry', () {
    test('no plugin depends on Google ML Kit, Firebase or data-transport libraries', () {
      // Plugins carry their own Android dependencies, which pubspec.yaml does
      // not show. A scanner built on ML Kit, for example, brings code that
      // reports usage to Google.
      final config = File('.dart_tool/package_config.json');
      if (!config.existsSync()) {
        markTestSkipped('run flutter pub get first');
        return;
      }
      final packages = (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
      const banned = [
        'com.google.mlkit',
        'com.google.android.gms:play-services-mlkit',
        'com.google.firebase',
        'com.google.android.datatransport',
        'play-services-analytics',
        'play-services-ads',
        'crashlytics',
        'com.facebook.android',
        'sentry',
      ];
      final offenders = <String>[];
      for (final entry in packages) {
        final map = entry as Map;
        final root = Uri.parse(map['rootUri'] as String);
        final dir = root.isAbsolute
            ? Directory.fromUri(root)
            : Directory.fromUri(config.parent.uri.resolveUri(root));
        for (final name in ['build.gradle', 'build.gradle.kts']) {
          final gradle = File('${dir.path}/android/$name');
          if (!gradle.existsSync()) continue;
          final text = gradle.readAsStringSync();
          for (final b in banned) {
            if (text.contains(b)) offenders.add('${map['name']}: $b');
          }
        }
      }
      expect(offenders, isEmpty, reason: 'telemetry libraries: $offenders');
    });
  });

  group('transfers are always encrypted', () {
    test('no certificate check accepts everything', () {
      final offenders = <String>[];
      for (final file in dartFiles) {
        final code = file.readAsStringSync();
        if (RegExp(r'badCertificateCallback\s*=\s*\([^)]*\)\s*=>\s*true').hasMatch(code)) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('every HttpClient in the app checks the peer fingerprint', () {
      for (final file in dartFiles) {
        final code = file.readAsStringSync();
        if (code.contains('HttpClient(')) {
          expect(code, contains('badCertificateCallback'), reason: file.path);
          expect(code, contains('fingerprintOfDer'), reason: file.path);
        }
      }
    });

    test('plain HTTP is served only by the browser share', () {
      final plain = [
        for (final file in dartFiles)
          if (RegExp(r'HttpServer\.bind\(').hasMatch(file.readAsStringSync())) file.path,
      ];
      expect(plain, hasLength(1));
      expect(plain.single.replaceAll(r'\', '/'), endsWith('web_share_server.dart'));
    });

    test('the main receiver only uses TLS', () {
      final receiver = File('lib/core/transfer/receive_server.dart').readAsStringSync();
      expect(receiver, contains('HttpServer.bindSecure'));
      expect(receiver, isNot(contains('HttpServer.bind(')));
    });

    test('senders refuse peers that only offer plain HTTP', () {
      final discovery = File('lib/core/discovery/multicast_discovery.dart').readAsStringSync();
      expect(discovery, contains('ProtocolScheme.https'));
      final send = File('lib/core/transfer/send_client.dart').readAsStringSync();
      expect(send, contains("scheme: 'https'"));
      expect(send, isNot(contains("scheme: 'http'")));
    });
  });

  group('received names are sanitized', () {
    test('every place a received file name becomes a path goes through the sanitizer', () {
      final receiver = File('lib/core/transfer/receive_server.dart').readAsStringSync();
      expect(RegExp('sanitizeReceivedFileName').allMatches(receiver).length, greaterThanOrEqualTo(2));
      // The destination is also checked to stay inside the download folder.
      expect(receiver, contains('p.isWithin(root, candidate)'));
    });

    test('the browser share keeps the same checks by reusing the receiver', () {
      final web = File('lib/core/transfer/web_share_server.dart').readAsStringSync();
      expect(web, contains('receiver.handleRequest'));
    });
  });

  group('the browser page', () {
    test('loads nothing from outside and restricts what it may do', () {
      final server = File('lib/core/transfer/web_share_server.dart').readAsStringSync();
      expect(server, contains("default-src 'none'"));
      expect(server, contains("connect-src 'self'"));
    });

    test('device names reach the page only as escaped data', () {
      final page = File('lib/core/transfer/web_share_page.dart').readAsStringSync();
      expect(page, contains('scriptSafeJson'));
      expect(page, isNot(contains('innerHTML')));
      expect(page, isNot(contains('document.write')));
      expect(page, isNot(contains('eval(')));
    });
  });

  group('platform folders', () {
    test('iOS code is not added before phase 6', () {
      final swift = Directory('ios')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.swift') && !f.path.contains('Pods'))
          .map((f) => f.path.replaceAll(r'\', '/'))
          .toList();
      // Only the Flutter-generated files are allowed.
      expect(
        swift.where((p) => !p.endsWith('AppDelegate.swift') &&
            !p.endsWith('SceneDelegate.swift') &&
            !p.endsWith('GeneratedPluginRegistrant.swift') &&
            !p.contains('RunnerTests')),
        isEmpty,
      );
    });
  });
}
