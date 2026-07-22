import 'package:app_data/app_data.dart';
import 'package:flutter/foundation.dart';

/// 向 Feature 暴露当前用户快照和变化通知，不暴露壳工程 Service。
abstract interface class CurrentUserProvider
    implements ValueListenable<UserEntity?> {}
