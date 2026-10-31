import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zajel/core/transfer/protocol_models.dart';

void main() {
  group('DeviceInfo', () {
    test('parses the register body from the protocol spec', () {
      final info = DeviceInfo.fromJson(
        jsonDecode('''
{"alias":"Secret Banana","version":"2.0","deviceModel":"Windows",
 "deviceType":"desktop","fingerprint":"abc","port":53317,
 "protocol":"https","download":true}''')
            as Map<String, dynamic>,
      );
      expect(info.alias, 'Secret Banana');
      expect(info.deviceType, DeviceType.desktop);
      expect(info.protocol, ProtocolScheme.https);
      expect(info.download, isTrue);
      expect(info.port, 53317);
    });

    test('tolerates missing optional fields and unknown device types', () {
      final info = DeviceInfo.fromJson({
        'alias': 'Old app',
        'fingerprint': 'f',
        'deviceType': 'toaster',
      });
      expect(info.deviceType, DeviceType.desktop);
      expect(info.port, localSendDefaultPort);
      expect(info.protocol, ProtocolScheme.https);
      expect(info.download, isFalse);
      expect(info.deviceModel, isNull);
    });

    test('toJson round-trips', () {
      const info = DeviceInfo(
        alias: 'Zajel',
        fingerprint: 'fp',
        deviceModel: 'Pixel',
        deviceType: DeviceType.mobile,
      );
      final copy = DeviceInfo.fromJson(info.toJson());
      expect(copy.alias, info.alias);
      expect(copy.fingerprint, info.fingerprint);
      expect(copy.deviceModel, info.deviceModel);
      expect(copy.deviceType, info.deviceType);
    });

    test('info body has no port or protocol', () {
      const info = DeviceInfo(alias: 'a', fingerprint: 'f');
      expect(info.toInfoJson().containsKey('port'), isFalse);
      expect(info.toInfoJson().containsKey('protocol'), isFalse);
    });
  });

  group('MulticastMessage', () {
    const device = DeviceInfo(alias: 'a', fingerprint: 'f');

    test('sends both announce and the legacy announcement field', () {
      final json = const MulticastMessage(device: device, announce: true).toJson();
      expect(json['announce'], isTrue);
      expect(json['announcement'], isTrue);
    });

    test('reads either field', () {
      expect(
        MulticastMessage.fromJson({'alias': 'a', 'fingerprint': 'f', 'announce': true})
            .announce,
        isTrue,
      );
      expect(
        MulticastMessage.fromJson({'alias': 'a', 'fingerprint': 'f', 'announcement': true})
            .announce,
        isTrue,
      );
      expect(
        MulticastMessage.fromJson({'alias': 'a', 'fingerprint': 'f'}).announce,
        isFalse,
      );
    });
  });

  group('prepare-upload', () {
    test('parses the request from the protocol spec', () {
      final request = PrepareUploadRequest.fromJson(
        jsonDecode('''
{"info":{"alias":"Nice Orange","version":"2.0","fingerprint":"x","port":53317,"protocol":"https"},
 "files":{"id1":{"id":"id1","fileName":"my image.png","size":324242,
 "fileType":"image/jpeg","sha256":"aa","preview":null,
 "metadata":{"modified":"2021-01-01T12:34:56Z","accessed":null}}}}''')
            as Map<String, dynamic>,
      );
      final file = request.files['id1']!;
      expect(file.fileName, 'my image.png');
      expect(file.size, 324242);
      expect(file.sha256, 'aa');
      expect(file.modified, DateTime.utc(2021, 1, 1, 12, 34, 56));
      expect(file.accessed, isNull);
    });

    test('rejects a file entry without a size', () {
      expect(
        () => PrepareUploadRequest.fromJson({
          'info': {'alias': 'a', 'fingerprint': 'f'},
          'files': {
            'x': {'id': 'x', 'fileName': 'f'},
          },
        }),
        throwsA(anything),
      );
    });

    test('response round-trips', () {
      const response = PrepareUploadResponse(
        sessionId: 's',
        files: {'a': 'tokenA'},
      );
      final copy = PrepareUploadResponse.fromJson(response.toJson());
      expect(copy.sessionId, 's');
      expect(copy.files, {'a': 'tokenA'});
    });
  });
}
