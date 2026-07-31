import 'package:app_core/app_core.dart';

import 'media_resource_models.dart';

abstract interface class MediaResourceStore {
  Future<MediaImportResult> importFile(MediaImportRequest request);

  Future<MediaResourceResult<MediaResourceLease>> retain(
    MediaResourceId resourceId,
  );

  Future<MediaResourceResult<ResolvedMediaResource>> resolve(
    MediaResourceId resourceId,
    MediaResourceLease lease,
  );

  Future<MediaResourceResult<void>> release(MediaResourceLease lease);

  Future<void> dispose();
}
