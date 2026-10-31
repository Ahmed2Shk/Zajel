import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zajel/app.dart';
import 'package:zajel/core/media/media_library.dart';
import 'package:zajel/core/platform/platform_api.g.dart';
import 'package:zajel/core/platform/platform_providers.dart';
import 'package:zajel/core/router/app_router.dart';
import 'package:zajel/core/transfer/transfer_providers.dart';
import 'package:zajel/features/settings/app_settings.dart';

import 'support/transfer_harness.dart';

final _png = base64.decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// A phone's gallery for tests. Records what the screen asked for.
class _FakeLibrary implements MediaLibrary {
  _FakeLibrary({
    this.images = 0,
    this.videos = 0,
    this.access = MediaAccess.granted,
    this.files = const {},
  });

  final int images;
  final int videos;
  MediaAccess access;

  /// item id -> the file it resolves to (missing means unreadable).
  final Map<String, ({String path, String name})> files;

  final accessRequests = <MediaKind>[];
  final pageRequests = <(MediaKind, int)>[];
  var settingsOpened = false;

  @override
  Future<MediaAccess> requestAccess(MediaKind kind) async {
    accessRequests.add(kind);
    return access;
  }

  @override
  Future<List<MediaItem>> page(MediaKind kind, {required int page, required int size}) async {
    pageRequests.add((kind, page));
    final total = kind == MediaKind.image ? images : videos;
    final start = page * size;
    final end = (start + size).clamp(0, total);
    return [
      for (var i = start; i < end; i++)
        MediaItem(
          id: '${kind.name}$i',
          kind: kind,
          duration: kind == MediaKind.video ? Duration(seconds: 65 + i) : null,
          thumbnail: (px) async => Uint8List.fromList(_png),
          resolve: () async => files['${kind.name}$i'],
        ),
    ];
  }

  @override
  Future<void> openSettings() async => settingsOpened = true;
}

Future<ProviderContainer> _pump(WidgetTester tester, {List<Override> overrides = const []}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      localSendServiceProvider.overrideWith((ref) async => null),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const ZajelApp()));
  await tester.pumpAndSettle();
  container.read(appRouterProvider).go(AppRoutes.filePicker);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  // Let the gallery and the pictures arrive (each takes a frame or two).
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

Future<({String path, String name})> _realFile(WidgetTester tester, String name, int size) async {
  final dir = Directory.systemTemp.createTempSync('zajel_media_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final path = await tester.runAsync(() async => (await writeTestFile(dir, name, size)).path);
  return (path: path!, name: name);
}

void main() {
  testWidgets('photos appear on their own, without pressing anything', (tester) async {
    final library = _FakeLibrary(images: 12);
    await _pump(tester, overrides: [mediaLibraryProvider.overrideWithValue(library)]);

    expect(library.accessRequests, [MediaKind.image]);
    expect(find.byType(Image), findsNWidgets(12));
    expect(find.text('اختيار صور'), findsNothing, reason: 'no button needed any more');
  });

  testWidgets('permission is asked only for the tab that is opened', (tester) async {
    final library = _FakeLibrary(images: 3, videos: 3);
    await _pump(tester, overrides: [mediaLibraryProvider.overrideWithValue(library)]);
    expect(library.accessRequests, [MediaKind.image]);

    await tester.tap(find.text('الفيديو'));
    await tester.pump();
    await _settle(tester);
    expect(library.accessRequests, [MediaKind.image, MediaKind.video]);
    expect(find.text('1:05'), findsOneWidget, reason: 'videos show their length');
  });

  testWidgets('going back to a tab keeps what was loaded', (tester) async {
    final library = _FakeLibrary(images: 5, videos: 5);
    await _pump(tester, overrides: [mediaLibraryProvider.overrideWithValue(library)]);
    await tester.tap(find.text('الفيديو'));
    await _settle(tester);
    await tester.tap(find.text('الصور'));
    await _settle(tester);
    expect(library.accessRequests, [MediaKind.image, MediaKind.video], reason: 'no second request');
    expect(library.pageRequests.where((p) => p.$1 == MediaKind.image), hasLength(1));
  });

  testWidgets('more photos load as you scroll to the end', (tester) async {
    final library = _FakeLibrary(images: 200);
    await _pump(tester, overrides: [mediaLibraryProvider.overrideWithValue(library)]);
    expect(library.pageRequests, [(MediaKind.image, 0)]);

    await tester.drag(find.byType(GridView), const Offset(0, -6000));
    await tester.pump();
    await _settle(tester);
    expect(library.pageRequests.length, greaterThan(1));
    expect(library.pageRequests[1], (MediaKind.image, 1));
  });

  testWidgets('tapping a photo selects it and tapping again removes it', (tester) async {
    final file = await _realFile(tester, 'IMG_1.jpg', 2048);
    final library = _FakeLibrary(images: 3, files: {'image1': file});
    final container = await _pump(tester, overrides: [mediaLibraryProvider.overrideWithValue(library)]);

    await tester.tap(find.byType(Image).at(1));
    await tester.pump();
    await _settle(tester);

    final selected = container.read(selectedFilesProvider);
    expect(selected, hasLength(1));
    expect(selected.single.id, 'media-image1');
    expect(selected.single.name, 'IMG_1.jpg');
    expect(selected.single.size, 2048);
    expect(find.text('إرسال (1)'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.byType(Image).at(1));
    await tester.pump();
    expect(container.read(selectedFilesProvider), isEmpty);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('a photo that cannot be read says so and is not selected', (tester) async {
    final library = _FakeLibrary(images: 2);
    final container = await _pump(tester, overrides: [mediaLibraryProvider.overrideWithValue(library)]);
    await tester.tap(find.byType(Image).first);
    await tester.pump();
    await _settle(tester);
    expect(find.text('تعذّر قراءة هذا الملف'), findsOneWidget);
    expect(container.read(selectedFilesProvider), isEmpty);
  });

  testWidgets('photos and videos selected together are both sent', (tester) async {
    final photo = await _realFile(tester, 'a.jpg', 100);
    final video = await _realFile(tester, 'b.mp4', 200);
    final library = _FakeLibrary(images: 1, videos: 1, files: {'image0': photo, 'video0': video});
    final container = await _pump(tester, overrides: [mediaLibraryProvider.overrideWithValue(library)]);

    await tester.tap(find.byType(Image).first);
    await _settle(tester);
    expect(container.read(selectedFilesProvider).map((f) => f.name), ['a.jpg']);

    await tester.tap(find.text('الفيديو'));
    await _settle(tester);
    // The photos tab stays built behind the videos tab, so the videos grid is the last one.
    await tester.tap(find.byType(Image).last);
    await _settle(tester);

    expect(container.read(selectedFilesProvider).map((f) => f.name), ['a.jpg', 'b.mp4']);
    expect(find.text('إرسال (2)'), findsOneWidget);
  });

  group('access', () {
    testWidgets('denied shows a clear message with ways to fix it', (tester) async {
      final library = _FakeLibrary(images: 3, access: MediaAccess.denied);
      await _pump(tester, overrides: [mediaLibraryProvider.overrideWithValue(library)]);
      expect(find.text('نحتاج إذن الوصول إلى الصور والفيديو لعرضها هنا.'), findsOneWidget);
      expect(find.byType(Image), findsNothing);

      await tester.tap(find.text('فتح الإعدادات'));
      expect(library.settingsOpened, isTrue);

      // After the user allows it, "Allow access" loads the photos.
      library.access = MediaAccess.granted;
      await tester.tap(find.text('السماح بالوصول'));
      await tester.pump();
      await _settle(tester);
      expect(find.byType(Image), findsNWidgets(3));
    });

    testWidgets('partial access still shows the allowed photos, with a note', (tester) async {
      final library = _FakeLibrary(images: 2, access: MediaAccess.limited);
      await _pump(tester, overrides: [mediaLibraryProvider.overrideWithValue(library)]);
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.textContaining('سمحت بجزء من الصور فقط'), findsOneWidget);
    });

    testWidgets('an empty gallery says so', (tester) async {
      await _pump(tester, overrides: [mediaLibraryProvider.overrideWithValue(_FakeLibrary())]);
      expect(find.text('لا توجد عناصر'), findsOneWidget);
    });

    testWidgets('a platform without a gallery points to the Files tab', (tester) async {
      await _pump(tester);
      expect(find.textContaining('استخدم تبويب الملفات'), findsOneWidget);
    });
  });

  group('apps', () {
    final apps = [
      NativeAppInfo(name: 'Alpha', packageName: 'com.alpha', apkPath: '/data/app/alpha.apk', size: 5 * 1024 * 1024),
      NativeAppInfo(name: 'Beta', packageName: 'com.beta', apkPath: '/data/app/beta.apk', size: 7 * 1024 * 1024),
    ];

    testWidgets('each app shows its own icon, and a placeholder until it loads', (tester) async {
      final asked = <String>[];
      await _pump(tester, overrides: [
        installedAppsProvider.overrideWith((ref) async => apps),
        appIconProvider.overrideWith((ref, pkg) async {
          asked.add(pkg);
          return pkg == 'com.alpha' ? Uint8List.fromList(_png) : null;
        }),
      ]);
      await tester.tap(find.text('التطبيقات'));
      await tester.pump();
      await _settle(tester);

      expect(asked, containsAll(['com.alpha', 'com.beta']));
      expect(find.byType(Image), findsOneWidget, reason: 'Alpha has an icon');
      expect(find.byIcon(Icons.android), findsOneWidget, reason: 'Beta falls back to the placeholder');
    });

    testWidgets('the list shows names and sizes', (tester) async {
      await _pump(tester, overrides: [
        installedAppsProvider.overrideWith((ref) async => apps),
        appIconProvider.overrideWith((ref, pkg) async => null),
      ]);
      await tester.tap(find.text('التطبيقات'));
      await _settle(tester);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('5.0 MB'), findsOneWidget);
    });

    testWidgets('search narrows the list', (tester) async {
      await _pump(tester, overrides: [
        installedAppsProvider.overrideWith((ref) async => apps),
        appIconProvider.overrideWith((ref, pkg) async => null),
      ]);
      await tester.tap(find.text('التطبيقات'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'bet');
      await tester.pump();
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Beta'), findsOneWidget);
    });
  });

  testWidgets('the selection can be reviewed and cleared from the send bar', (tester) async {
    final file = await _realFile(tester, 'a.jpg', 100);
    final library = _FakeLibrary(images: 1, files: {'image0': file});
    final container = await _pump(tester, overrides: [mediaLibraryProvider.overrideWithValue(library)]);
    await tester.tap(find.byType(Image).first);
    await _settle(tester);

    await tester.tap(find.textContaining('مراجعة المحدد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('a.jpg'), findsOneWidget);

    await tester.tap(find.text('إلغاء التحديد'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(selectedFilesProvider), isEmpty);
  });
}

/// Lets real file work finish (it does not run on a widget test's fake clock)
/// and then gives the screen a couple of frames to show the result.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}
