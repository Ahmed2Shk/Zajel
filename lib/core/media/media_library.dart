import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

enum MediaKind { image, video }

enum MediaAccess {
  granted,

  /// Android 14+: the user shared only some photos. Those still work.
  limited,
  denied,
}

/// A photo or video on the device. The picture is loaded when the tile is
/// shown, and the file path only when it is selected.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.kind,
    required this.thumbnail,
    required this.resolve,
    this.title,
    this.duration,
  });

  final String id;
  final MediaKind kind;
  final String? title;
  final Duration? duration;

  /// A small square picture, [px] pixels wide, or null if it cannot be made.
  final Future<Uint8List?> Function(int px) thumbnail;

  /// Where the file is and what it is called, or null if it cannot be read.
  final Future<({String path, String name})?> Function() resolve;
}

/// The photos and videos on the device. An interface so screens can be tested
/// without a phone.
abstract class MediaLibrary {
  Future<MediaAccess> requestAccess(MediaKind kind);

  /// Newest first. Fewer than [size] items means the end was reached.
  Future<List<MediaItem>> page(MediaKind kind, {required int page, required int size});

  Future<void> openSettings();
}

class PhotoManagerMediaLibrary implements MediaLibrary {
  AssetPathEntity? _images;
  AssetPathEntity? _videos;

  RequestType _type(MediaKind kind) =>
      kind == MediaKind.image ? RequestType.image : RequestType.video;

  @override
  Future<MediaAccess> requestAccess(MediaKind kind) async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: PermissionRequestOption(
        androidPermission: AndroidPermission(type: _type(kind), mediaLocation: false),
      ),
    );
    if (state == PermissionState.limited) return MediaAccess.limited;
    return state.hasAccess ? MediaAccess.granted : MediaAccess.denied;
  }

  Future<AssetPathEntity?> _album(MediaKind kind) async {
    final cached = kind == MediaKind.image ? _images : _videos;
    if (cached != null) return cached;
    final albums = await PhotoManager.getAssetPathList(
      type: _type(kind),
      onlyAll: true, // the "all photos" album, not one per folder
      filterOption: FilterOptionGroup(
        orders: [const OrderOption(type: OrderOptionType.createDate)],
      ),
    );
    final album = albums.isEmpty ? null : albums.first;
    if (kind == MediaKind.image) {
      _images = album;
    } else {
      _videos = album;
    }
    return album;
  }

  @override
  Future<List<MediaItem>> page(MediaKind kind, {required int page, required int size}) async {
    final album = await _album(kind);
    if (album == null) return const [];
    final assets = await album.getAssetListPaged(page: page, size: size);
    return [for (final a in assets) _item(a, kind)];
  }

  MediaItem _item(AssetEntity asset, MediaKind kind) => MediaItem(
    id: asset.id,
    kind: kind,
    duration: kind == MediaKind.video ? asset.videoDuration : null,
    thumbnail: (px) => asset.thumbnailDataWithSize(ThumbnailSize.square(px)),
    resolve: () => _resolve(asset),
  );

  /// Prefers the real path on disk. `originFile` can copy the whole file into
  /// the app's cache on newer Android, which is slow and doubles the space for a
  /// big video, so it is only the fallback.
  Future<({String path, String name})?> _resolve(AssetEntity asset) async {
    final name = await asset.titleAsync;
    if (!kIsWeb && Platform.isAndroid && name.isNotEmpty) {
      final relative = asset.relativePath;
      if (relative != null) {
        final direct = File('/storage/emulated/0/$relative$name');
        if (direct.existsSync()) return (path: direct.path, name: name);
      }
    }
    final file = await asset.originFile;
    if (file == null) return null;
    return (path: file.path, name: name.isEmpty ? file.uri.pathSegments.last : name);
  }

  @override
  Future<void> openSettings() => PhotoManager.openSetting();
}

/// Photos and videos. Only Android and iOS have a media store to read.
final mediaLibraryProvider = Provider<MediaLibrary?>((ref) {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return null;
  return PhotoManagerMediaLibrary();
});
