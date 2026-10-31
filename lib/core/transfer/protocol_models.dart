/// Wire models for the LocalSend v2 protocol (https://github.com/localsend/protocol).
///
/// Parsing is lenient on purpose: other implementations omit optional fields
/// and send unknown device types.
library;

const localSendApiPrefix = '/api/localsend/v2';
const localSendDefaultPort = 53317;
const localSendMulticastAddress = '224.0.0.167';
const zajelProtocolVersion = '2.1';

/// Zajel-only extensions, negotiated through HTTP headers so that the official
/// LocalSend apps (which ignore unknown headers) are never affected.
///
/// A Zajel sender adds the header to `prepare-upload`; a Zajel receiver echoes
/// it in the response. Only then does the sender use chunked, parallel uploads.
const zajelExtensionHeader = 'x-zajel-extension';
const zajelExtensionVersion = '1';
/// A Zajel receiver with a native data path tells the sender where to send chunks.
const zajelDataPortHeader = 'x-zajel-data-port';
const zajelProgressRoute = '$localSendApiPrefix/zajel/progress';
const zajelBenchmarkRoute = '$localSendApiPrefix/zajel/benchmark';

enum DeviceType {
  mobile,
  desktop,
  web,
  headless,
  server;

  /// Unknown values fall back to [desktop], like the official implementation.
  static DeviceType parse(Object? value) {
    for (final type in values) {
      if (type.name == value) return type;
    }
    return desktop;
  }
}

enum ProtocolScheme {
  http,
  https;

  static ProtocolScheme parse(Object? value) =>
      value == 'http' ? http : https;
}

class DeviceInfo {
  const DeviceInfo({
    required this.alias,
    required this.fingerprint,
    this.version = zajelProtocolVersion,
    this.deviceModel,
    this.deviceType = DeviceType.mobile,
    this.port = localSendDefaultPort,
    this.protocol = ProtocolScheme.https,
    this.download = false,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
    alias: json['alias'] as String? ?? 'Unknown',
    version: json['version'] as String? ?? '2.0',
    deviceModel: json['deviceModel'] as String?,
    deviceType: DeviceType.parse(json['deviceType']),
    fingerprint: json['fingerprint'] as String? ?? '',
    port: (json['port'] as num?)?.toInt() ?? localSendDefaultPort,
    protocol: ProtocolScheme.parse(json['protocol']),
    download: json['download'] as bool? ?? false,
  );

  final String alias;
  final String version;
  final String? deviceModel;
  final DeviceType deviceType;
  final String fingerprint;
  final int port;
  final ProtocolScheme protocol;
  final bool download;

  Map<String, dynamic> toJson() => {
    'alias': alias,
    'version': version,
    'deviceModel': deviceModel,
    'deviceType': deviceType.name,
    'fingerprint': fingerprint,
    'port': port,
    'protocol': protocol.name,
    'download': download,
  };

  /// Body of `GET /info` and of the `/register` response: no port or protocol.
  Map<String, dynamic> toInfoJson() => {
    'alias': alias,
    'version': version,
    'deviceModel': deviceModel,
    'deviceType': deviceType.name,
    'fingerprint': fingerprint,
    'download': download,
  };
}

/// UDP multicast message. Carries both the current `announce` field and the
/// legacy `announcement` field so that old and new apps both react to it.
class MulticastMessage {
  const MulticastMessage({required this.device, required this.announce});

  factory MulticastMessage.fromJson(Map<String, dynamic> json) =>
      MulticastMessage(
        device: DeviceInfo.fromJson(json),
        announce:
            json['announce'] as bool? ?? json['announcement'] as bool? ?? false,
      );

  final DeviceInfo device;
  final bool announce;

  Map<String, dynamic> toJson() => {
    ...device.toJson(),
    'announce': announce,
    'announcement': announce,
  };
}

class FileMetadata {
  const FileMetadata({
    required this.id,
    required this.fileName,
    required this.size,
    required this.fileType,
    this.sha256,
    this.preview,
    this.modified,
    this.accessed,
  });

  factory FileMetadata.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'] as Map<String, dynamic>?;
    return FileMetadata(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      size: (json['size'] as num).toInt(),
      fileType: json['fileType'] as String? ?? 'application/octet-stream',
      sha256: json['sha256'] as String?,
      preview: json['preview'] as String?,
      modified: _parseDate(metadata?['modified']),
      accessed: _parseDate(metadata?['accessed']),
    );
  }

  final String id;
  final String fileName;
  final int size;
  final String fileType;
  final String? sha256;
  final String? preview;
  final DateTime? modified;
  final DateTime? accessed;

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'size': size,
    'fileType': fileType,
    'sha256': sha256,
    'preview': preview,
    if (modified != null || accessed != null)
      'metadata': {
        'modified': modified?.toUtc().toIso8601String(),
        'accessed': accessed?.toUtc().toIso8601String(),
      },
  };

  static DateTime? _parseDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

class PrepareUploadRequest {
  const PrepareUploadRequest({required this.info, required this.files});

  factory PrepareUploadRequest.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'] as Map<String, dynamic>;
    return PrepareUploadRequest(
      info: DeviceInfo.fromJson(json['info'] as Map<String, dynamic>),
      files: {
        for (final entry in rawFiles.entries)
          entry.key: FileMetadata.fromJson(
            entry.value as Map<String, dynamic>,
          ),
      },
    );
  }

  final DeviceInfo info;
  final Map<String, FileMetadata> files;

  Map<String, dynamic> toJson() => {
    'info': info.toJson(),
    'files': {for (final e in files.entries) e.key: e.value.toJson()},
  };
}

class PrepareUploadResponse {
  const PrepareUploadResponse({required this.sessionId, required this.files});

  factory PrepareUploadResponse.fromJson(Map<String, dynamic> json) =>
      PrepareUploadResponse(
        sessionId: json['sessionId'] as String,
        files: Map<String, String>.from(json['files'] as Map),
      );

  final String sessionId;

  /// File id -> upload token. Declined files are absent.
  final Map<String, String> files;

  Map<String, dynamic> toJson() => {'sessionId': sessionId, 'files': files};
}
