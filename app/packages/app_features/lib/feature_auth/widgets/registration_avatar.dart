import 'dart:typed_data';

import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

final class RegistrationAvatar extends StatelessWidget {
  const RegistrationAvatar({
    required this.bytes,
    required this.isPicking,
    required this.onPressed,
    super.key,
  });

  final Uint8List? bytes;
  final bool isPicking;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: bytes == null ? 'Add profile photo' : 'Change profile photo',
    child: ExcludeSemantics(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: 90,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (bytes case final imageBytes?)
                  ClipOval(
                    child: Image.memory(
                      imageBytes,
                      width: 82,
                      height: 82,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      excludeFromSemantics: true,
                    ),
                  )
                else ...[
                  Image.asset(
                    'assets/images/auth/registration_photo_placeholder.png',
                    package: 'app_features',
                    width: 90,
                    height: 90,
                    excludeFromSemantics: true,
                  ),
                  const Icon(
                    Icons.camera_alt_outlined,
                    color: AppColors.primary,
                    size: 34,
                  ),
                ],
                if (isPicking)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0x66FFFFFF),
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(
                      dimension: 82,
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
