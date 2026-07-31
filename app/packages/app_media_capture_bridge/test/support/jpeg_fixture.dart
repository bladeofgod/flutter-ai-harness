import 'dart:convert';
import 'dart:typed_data';

const String _onePixelJpegBase64 =
    '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////'
    '////////////////////////////////////////////////////////2wBDAf//'
    '////////////////////////////////////////////////////////////////////'
    '////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAA'
    'AAAAAAf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAF//8QAFBAB'
    'AAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAA'
    'AP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPwF//8QA'
    'FBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QAFBABAAAAAAAAAAAAAAAA'
    'AAAAAP/aAAgBAQABPyF//9oADAMBAAIAAwAAABD/xAAUEQEAAAAAAAAAAAAAAAAA'
    'AAAA/9oACAEDAQE/EH//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/EH//'
    'xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/EH//2Q==';

Uint8List validSanitizedJpeg() => base64Decode(_onePixelJpegBase64);

Uint8List jpegWithExifSegment() {
  final jpeg = validSanitizedJpeg();
  return Uint8List.fromList(<int>[
    0xff,
    0xd8,
    0xff,
    0xe1,
    0x00,
    0x08,
    0x45,
    0x78,
    0x69,
    0x66,
    0x00,
    0x00,
    ...jpeg.skip(2),
  ]);
}

Uint8List jpegWithJfifSuffix() {
  final jpeg = validSanitizedJpeg();
  return Uint8List.fromList(<int>[
    ...jpeg.take(4),
    0x00,
    0x14,
    ...jpeg.skip(6).take(14),
    0x6e,
    0x61,
    0x6d,
    0x65,
    ...jpeg.skip(20),
  ]);
}

Uint8List jpegWithIccSegment() {
  final jpeg = validSanitizedJpeg();
  return Uint8List.fromList(<int>[
    0xff,
    0xd8,
    0xff,
    0xe2,
    0x00,
    0x12,
    ...'ICC_PROFILE\u0000name'.codeUnits,
    ...jpeg.skip(2),
  ]);
}

Uint8List jpegWithScanBeforeFrame() => Uint8List.fromList(<int>[
  0xff,
  0xd8,
  0xff,
  0xda,
  0x00,
  0x02,
  0xff,
  0xc0,
  0x00,
  0x08,
  0x08,
  0x00,
  0x01,
  0x00,
  0x01,
  0x00,
  0xff,
  0xd9,
]);
