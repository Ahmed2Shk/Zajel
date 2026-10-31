import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_log.dart';

/// The local log. Null in tests and wherever it could not be opened.
final appLogProvider = Provider<AppLog?>((ref) => null);
