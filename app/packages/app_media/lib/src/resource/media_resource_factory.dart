import 'package:path_provider/path_provider.dart';

import 'default_media_resource_store.dart';
import 'flutter_image_canonicalizer.dart';
import 'local_media_resource_file_system.dart';
import 'media_resource_store.dart';
import 'media_resource_support.dart';

Future<MediaResourceStore>? _processStore;

/// Creates the process-scoped store using the platform app-cache directory.
Future<MediaResourceStore> createMediaResourceStore() {
  return _processStore ??= _createProcessStore();
}

Future<MediaResourceStore> _createProcessStore() async {
  try {
    return await DefaultMediaResourceStore.create(
      fileSystem: LocalMediaResourceFileSystem(
        cacheDirectoryProvider: getTemporaryDirectory,
      ),
      imageCanonicalizer: const FlutterMediaImageCanonicalizer(),
      random: SecureMediaResourceRandom(),
      clock: const SystemMediaResourceClock(),
    );
  } on Object {
    _processStore = null;
    rethrow;
  }
}
