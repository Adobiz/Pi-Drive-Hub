/// 123 云盘请求签名算法（复刻 alist 123 驱动）。
///
/// 每个 API 请求的 URL 需追加动态签名参数：
/// 1. 当前时间(CST) `yyyyMMddHHmm` 每位数字映射到 [table]，得映射串
/// 2. timeSign = crc32(映射串)
/// 3. data = timestamp|random|path|os|version|timeSign，dataSign = crc32(data)
/// 4. query 加 `timeSign=timestamp-random-dataSign`
library;

class Pan123Sign {
  static const List<int> _table = [
    0x61, 0x64, 0x65, 0x66, 0x67, 0x68, 0x6c, 0x6d, // a d e f g h l m
    0x79, 0x69, 0x6a, 0x6e, 0x6f, 0x70, 0x6b, 0x71, // y i j n o p k q
    0x72, 0x73, 0x74, 0x75, 0x62, 0x63, 0x76, 0x77, // r s t u b c v w
    0x73, 0x7a,                                     // s z
  ];

  /// 生成签名 query 参数（返回键值对）
  static MapEntry<String, String> sign(String path) {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8)); // CST
    final random = (10000000 * _randDouble()).round();

    final ts = now.millisecondsSinceEpoch ~/ 1000;
    final timeStr = _formatCst(now);
    final mapped = StringBuffer();
    for (var i = 0; i < timeStr.length; i++) {
      final digit = timeStr.codeUnitAt(i) - 0x30;
      mapped.writeCharCode(_table[digit]);
    }
    final timeSign = _crc32(mapped.toString());

    final data = '$ts|$random|$path|web|3|$timeSign';
    final dataSign = _crc32(data);
    return MapEntry('timeSign', '$ts-$random-$dataSign');
  }

  static String _formatCst(DateTime cst) {
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${cst.year}${p2(cst.month)}${p2(cst.day)}${p2(cst.hour)}${p2(cst.minute)}';
  }

  static double _randDouble() {
    // 简易伪随机（Dart Random 由调用方注入？这里用固定种子不可行，
    // 直接调用 Random）
    return _random.nextDouble();
  }

  static final _random = _SeededRandom();

  /// CRC32（IEEE，与 Go hash/crc32 一致）
  static String _crc32(String input) {
    final bytes = input.codeUnits;
    var crc = 0xFFFFFFFF;
    for (final b in bytes) {
      crc ^= b & 0xFF;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }
    return (crc ^ 0xFFFFFFFF).toUnsigned(32).toString();
  }
}

/// 简易随机数（避免每次 import dart:math）
class _SeededRandom {
  int _state = 0x12345678;
  double nextDouble() {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state / 0x7fffffff;
  }
}
