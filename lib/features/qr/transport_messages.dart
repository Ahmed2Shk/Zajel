import '../../core/transport/transport_manager.dart';
import '../../l10n/app_localizations.dart';

/// The text that tells the user what to do about each transport failure.
String transportMessage(AppLocalizations l10n, TransportFailure failure) => switch (failure) {
  TransportFailure.permissionDenied => l10n.tfPermission,
  TransportFailure.locationOff => l10n.tfLocation,
  TransportFailure.wifiOff => l10n.tfWifi,
  TransportFailure.unsupported => l10n.tfUnsupported,
  TransportFailure.busy => l10n.tfBusy,
  TransportFailure.timeout => l10n.tfTimeout,
  TransportFailure.failed => l10n.tfFailed,
};

/// A send job's error string `transport:<reason>` as a failure, or null.
TransportFailure? transportFailureOf(String? error) {
  if (error == null || !error.startsWith('transport:')) return null;
  final name = error.substring('transport:'.length);
  for (final f in TransportFailure.values) {
    if (f.name == name) return f;
  }
  return TransportFailure.failed;
}
