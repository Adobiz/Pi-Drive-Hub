import 'dart:io';
import 'package:crypto/crypto.dart';
import 'range_download.dart';

Future<String> hashFile(
  File file,
  Hash hash, {
  bool Function()? isCanceled,
  int? start,
  int? end,
}) async {
  checkTransfer(isCanceled);
  final stream = file.openRead(start, end).map((chunk) {
    checkTransfer(isCanceled);
    return chunk;
  });
  final digest = await hash.bind(stream).first;
  checkTransfer(isCanceled);
  return digest.toString();
}
