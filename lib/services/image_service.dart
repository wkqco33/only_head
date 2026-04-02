import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

final _picker = ImagePicker();

Future<File?> pickImage(ImageSource source) async {
  final xfile = await _picker.pickImage(source: source, imageQuality: 100);
  if (xfile == null) return null;
  return File(xfile.path);
}

Future<File> saveImageToTemp(Uint8List bytes, String filename) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes);
  return file;
}

/// 갤러리(사진 앱)에 이미지를 저장한다.
Future<void> saveImageToGallery(Uint8List bytes) async {
  final file = await saveImageToTemp(
    bytes,
    'only_head_${DateTime.now().millisecondsSinceEpoch}.png',
  );
  await Gal.putImage(file.path);
}

Future<void> shareImage(Uint8List bytes, String filename) async {
  final file = await saveImageToTemp(bytes, filename);
  await Share.shareXFiles([XFile(file.path)], text: 'Only Head');
}
