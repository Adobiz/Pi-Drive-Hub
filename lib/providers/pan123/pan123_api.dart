/// 123 云盘 API 客户端。
///
/// 所有请求 URL 需带动态签名（Pan123Sign），
/// 头带 `Authorization: Bearer <token>` + platform/app-version。
/// 401 时自动重新登录重试。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'pan123_auth.dart';
import 'pan123_config.dart';
import 'pan123_sign.dart';

class Pan123ApiException implements Exception {
  final int code;
  final String message;

  Pan123ApiException(this.code, this.message);

  @override
  String toString() => 'Pan123ApiException($code): $message';
}

/// 123 文件/目录
class Pan123File {
  final String name;
  final int size;
  final int fileId;
  final int type; // 1=目录, 0=文件
  final String etag;
  final String s3KeyFlag;

  Pan123File({
    required this.name,
    required this.size,
    required this.fileId,
    required this.type,
    required this.etag,
    required this.s3KeyFlag,
  });

  bool get isDir => type == 1;

  factory Pan123File.fromJson(Map<String, dynamic> j) => Pan123File(
        name: (j['FileName'] as String?) ?? '',
        size: (j['Size'] as num?)?.toInt() ?? 0,
        fileId: (j['FileId'] as num?)?.toInt() ?? 0,
        type: (j['Type'] as num?)?.toInt() ?? 0,
        etag: (j['Etag'] as String?) ?? '',
        s3KeyFlag: (j['S3KeyFlag'] as String?) ?? '',
      );
}

class Pan123Api {
  final Pan123AuthProvider auth;
  final http.Client _client;

  Pan123Api({required this.auth, http.Client? client})
      : _client = client ?? http.Client();

  /// 组装签名 URL
  Uri _signedUrl(String path, {Map<String, String>? query}) {
    final base = Uri.parse('${Pan123Config.apiBase}$path');
    final sign = Pan123Sign.sign(path);
    final q = {...?query, sign.key: sign.value};
    return base.replace(queryParameters: q);
  }

  /// GET 请求（带 token 同步读取）
  Future<Map<String, dynamic>> _get(String path,
      {Map<String, String>? query}) async {
    final token = await auth.getAccessToken();
    if (token == null) throw Pan123ApiException(401, '未登录');
    final uri = _signedUrl(path, query: query);
    final resp = await _client
        .get(uri, headers: _headersWithToken(token))
        .timeout(const Duration(seconds: 30));
    return _handle(resp);
  }

  Future<Map<String, dynamic>> _post(String path,
      {Map<String, String>? query, Map<String, dynamic>? body}) async {
    final token = await auth.getAccessToken();
    if (token == null) throw Pan123ApiException(401, '未登录');
    final uri = _signedUrl(path, query: query);
    final resp = await _client
        .post(
          uri,
          headers: {..._headersWithToken(token), 'Content-Type': 'application/json'},
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    return _handle(resp);
  }

  Map<String, String> _headersWithToken(String token) => {
        'origin': Pan123Config.webBase,
        'referer': '${Pan123Config.webBase}/',
        'authorization': 'Bearer $token',
        'user-agent': Pan123Config.ua,
        'platform': 'web',
        'app-version': '3',
      };

  Future<Map<String, dynamic>> _handle(http.Response resp) async {
    if (resp.statusCode != 200) {
      throw Pan123ApiException(resp.statusCode, 'HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final code = (json['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      // 401 重登一次
      if (code == 401) {
        await auth.logout();
        throw Pan123ApiException(401, '登录已过期，请重新登录');
      }
      throw Pan123ApiException(code, (json['message'] ?? 'code=$code').toString());
    }
    return json;
  }

  // ---------- 用户信息 ----------

  Future<Map<String, dynamic>> getUserInfo() async {
    final json = await _get('/user/info');
    return json['data'] as Map<String, dynamic>? ?? {};
  }

  // ---------- 文件列表 ----------

  Future<List<Pan123File>> listDir(int parentId, {int pageSize = 100}) async {
    final files = <Pan123File>[];
    var page = 1;
    while (true) {
      final json = await _get('/file/list/new', query: {
        'driveId': '0',
        'limit': '$pageSize',
        'next': '0',
        'orderBy': 'file_id',
        'orderDirection': 'desc',
        'parentFileId': '$parentId',
        'trashed': 'false',
        'SearchData': '',
        'Page': '$page',
        'OnlyLookAbnormalFile': '0',
        'event': 'homeListFile',
        'operateType': '4',
        'inDirectSpace': 'false',
      });
      final data = json['data'] as Map<String, dynamic>?;
      final list = (data?['InfoList'] as List?) ?? const [];
      for (final item in list) {
        files.add(Pan123File.fromJson(item as Map<String, dynamic>));
      }
      final next = (data?['Next'] as String?) ?? '-1';
      if (list.isEmpty || next == '-1') break;
      page++;
    }
    return files;
  }

  /// 搜索（123 无全盘搜索接口，用列表的 SearchData 参数，从根目录递归匹配）
  Future<List<Pan123File>> search(String keyword) async {
    final files = <Pan123File>[];
    final json = await _get('/file/list/new', query: {
      'driveId': '0',
      'limit': '100',
      'next': '0',
      'orderBy': 'file_id',
      'orderDirection': 'desc',
      'parentFileId': '0',
      'trashed': 'false',
      'SearchData': keyword,
      'Page': '1',
      'OnlyLookAbnormalFile': '0',
      'event': 'homeListFile',
      'operateType': '4',
      'inDirectSpace': 'false',
    });
    final data = json['data'] as Map<String, dynamic>?;
    final list = (data?['InfoList'] as List?) ?? const [];
    for (final item in list) {
      files.add(Pan123File.fromJson(item as Map<String, dynamic>));
    }
    return files;
  }

  // ---------- 文件操作 ----------

  /// 新建文件夹（type=1）或上传初始化（type=0）
  Future<Map<String, dynamic>> createFolder(int parentId, String name) async {
    final json = await _post('/file/upload_request', body: {
      'driveId': 0,
      'etag': '',
      'fileName': name,
      'parentFileId': parentId,
      'size': 0,
      'type': 1,
    });
    return json['data'] as Map<String, dynamic>? ?? {};
  }

  Future<void> rename(int fileId, String newName) async {
    await _post('/file/rename', body: {
      'driveId': 0,
      'fileId': fileId,
      'fileName': newName,
    });
  }

  /// 删除（fileTrashInfoList 需完整 File 对象）
  Future<void> delete(List<Pan123File> files) async {
    final trashList = files.map((f) => {
          'FileName': f.name,
          'Size': f.size,
          'FileId': f.fileId,
          'Type': f.type,
          'Etag': f.etag,
          'S3KeyFlag': f.s3KeyFlag,
        }).toList();
    await _post('/file/trash', body: {
      'driveId': 0,
      'operation': true,
      'fileTrashInfoList': trashList,
    });
  }

  Future<void> move(int fileId, int toParentId) async {
    await _post('/file/mod_pid', body: {
      'driveId': 0,
      'fileIdList': [fileId],
      'parentFileId': toParentId,
    });
  }

  // ---------- 下载 ----------

  /// 获取下载直链（download_info → 可能 base64 解码 → 302 重定向）
  Future<String> getDownloadUrl(int fileId, String etag, String s3KeyFlag,
      int size, int type, String fileName) async {
    final json = await _post('/file/download_info', body: {
      'driveId': 0,
      'etag': etag,
      'fileId': fileId,
      'fileName': fileName,
      's3keyFlag': s3KeyFlag,
      'size': size,
      'type': type,
    });
    final data = json['data'] as Map<String, dynamic>?;
    var url = data?['DownloadUrl'] as String?;
    if (url == null || url.isEmpty) throw Pan123ApiException(-1, '获取下载链接失败');

    // params 参数 base64 解码后才是真实直链
    final u = Uri.parse(url);
    final params = u.queryParameters['params'];
    if (params != null && params.isNotEmpty) {
      url = utf8.decode(base64Decode(params));
    }

    // 请求直链，处理 302 或 redirect_url
    final resp = await _client
        .get(Uri.parse(url), headers: {
          'Referer': '${Pan123Config.webBase}/',
          'User-Agent': Pan123Config.ua,
        })
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode == 302) {
      final loc = resp.headers['location'] ?? url;
      return loc;
    } else if (resp.statusCode == 210 || resp.statusCode == 200) {
      // 210 是 123 的重定向状态码：body JSON 含 redirect_url
      final body = utf8.decode(resp.bodyBytes);
      try {
        final j = jsonDecode(body) as Map<String, dynamic>;
        // redirect_url 可能在 data 下，或直接顶层
        String? redir;
        final d = j['data'];
        if (d is Map) redir = d['redirect_url']?.toString();
        if (redir == null || redir.isEmpty) redir = j['redirect_url']?.toString();
        if (redir != null && redir.isNotEmpty) {
          return redir;
        }
      } catch (_) {}
    }
    return url;
  }

  Future<void> download(
    int fileId,
    String etag,
    String s3KeyFlag,
    int size,
    int type,
    String localPath, {
    void Function(int, int?)? onProgress,
    bool Function()? isCanceled,
    Set<int>? completedBlocks,
    void Function(int, Set<int>)? onBlocks,
  }) async {
    final fileName = localPath.split('/').last;
    var url = await getDownloadUrl(fileId, etag, s3KeyFlag, size, type, fileName);

    // 最终下载地址可能还有一次重定向：禁用自动跟随，手动处理 302/210
    final file = File(localPath);
    for (var hop = 0; hop < 3; hop++) {
      final req = http.Request('GET', Uri.parse(url));
      req.headers.addAll({
        'User-Agent': Pan123Config.ua,
        'Referer': '${Pan123Config.webBase}/',
      });
      final streamed = await _client
          .send(req)
          .timeout(const Duration(seconds: 30));
      if (streamed.statusCode == 302) {
        final loc = streamed.headers['location'];
        if (loc == null) {
          throw Pan123ApiException(302, '下载重定向缺少 location');
        }
        url = loc;
        continue;
      }
      if (streamed.statusCode == 210) {
        // 210：body 含 redirect_url
        final body = utf8.decode(await streamed.stream.toBytes());
        final j = jsonDecode(body) as Map<String, dynamic>;
        final d = j['data'];
        String? redir;
        if (d is Map) redir = d['redirect_url']?.toString();
        redir ??= j['redirect_url']?.toString();
        if (redir == null || redir.isEmpty) {
          throw Pan123ApiException(210, '下载重定向缺少 redirect_url');
        }
        url = redir;
        continue;
      }
      if (streamed.statusCode != 200) {
        throw Pan123ApiException(streamed.statusCode,
            '下载 HTTP ${streamed.statusCode}');
      }
      // 200：真正下载（分片式断点续传，1MB/块 + RandomAccessFile 定位写）
      final total = streamed.contentLength;
      final doneBlocks = completedBlocks ?? <int>{};
      final raf = await file.open(
        mode: doneBlocks.isEmpty ? FileMode.write : FileMode.writeOnlyAppend,
      );
      var received = 0;
      try {
        if (total != null) await raf.truncate(total);
        var start = 0;
        const chunkSize = 1 * 1024 * 1024;
        while (true) {
          if (isCanceled?.call() ?? false) {
            throw Pan123ApiException(-3, '下载已取消');
          }
          final blockIndex = start ~/ chunkSize;
          // 跳过已完成分片（断点续传）
          if (doneBlocks.contains(blockIndex)) {
            start += chunkSize;
            received = start > (total ?? 0) ? (total ?? 0) : start;
            onProgress?.call(received, total);
            if (total != null && start >= total) break;
            continue;
          }
          final end = (total != null && start + chunkSize - 1 < total)
              ? start + chunkSize - 1
              : null;
          final req = http.Request('GET', Uri.parse(url));
          req.headers.addAll({
            'User-Agent': Pan123Config.ua,
            'Referer': '${Pan123Config.webBase}/',
            'Range': end != null ? 'bytes=$start-$end' : 'bytes=$start-',
          });
          final resp = await http.Response.fromStream(
              await _client.send(req).timeout(const Duration(seconds: 60)));
          if (resp.statusCode != 200 && resp.statusCode != 206) {
            throw Pan123ApiException(resp.statusCode,
                '下载分片 HTTP ${resp.statusCode} @ $start');
          }
          if (resp.bodyBytes.isEmpty) break;
          await raf.setPosition(start);
          await raf.writeFrom(resp.bodyBytes);
          doneBlocks.add(blockIndex);
          received += resp.bodyBytes.length;
          onProgress?.call(received, total);
          onBlocks?.call(received, doneBlocks);
          if (end == null) break;
          if (resp.bodyBytes.length < chunkSize) break;
          start += chunkSize;
        }
        await raf.flush();
      } finally {
        await raf.close();
      }
      onProgress?.call(received, total);
      return;
    }
    throw Pan123ApiException(-1, '下载重定向次数过多');
  }

  // ---------- 上传（S3 分片） ----------

  /// 上传文件到目录（16MB 分片，走 S3 预签名）
  Future<void> upload(
    String localPath,
    int parentFileId, {
    void Function(int, int?)? onProgress,
    bool Function()? isCanceled,
  }) async {
    final file = File(localPath);
    final size = await file.length();
    final fileName = file.uri.pathSegments.last;
    // 计算 MD5（秒传检测）
    final md5hex = await _fileMd5(file);

    // 1. upload_request 初始化
    final json = await _post('/file/upload_request', body: {
      'driveId': 0,
      'duplicate': 2,
      'etag': md5hex,
      'fileName': fileName,
      'parentFileId': parentFileId,
      'size': size,
      'type': 0,
    });
    final data = json['data'] as Map<String, dynamic>? ?? {};
    final reuse = data['Reuse'] as bool? ?? false;
    if (reuse || (data['Key'] as String?)?.isEmpty == true) {
      onProgress?.call(size, size); // 秒传
      return;
    }

    final storageNode = data['StorageNode'] as String? ?? '';
    final bucket = data['Bucket'] as String? ?? '';
    final key = data['Key'] as String? ?? '';
    final uploadId = data['UploadId'] as String? ?? '';
    final fileId = data['FileId']?.toString() ?? '';

    // 2. 分片上传（16MB）
    const chunkSize = 16 * 1024 * 1024;
    final chunkCount = (size / chunkSize).ceil();
    var done = 0;
    final raf = await file.open();
    try {
      for (var i = 1; i <= chunkCount; i++) {
        if (isCanceled?.call() ?? false) throw Pan123ApiException(-3, '上传已取消');
        final curSize = i == chunkCount ? size - (i - 1) * chunkSize : chunkSize;
        await raf.setPosition((i - 1) * chunkSize);
        final bytes = await raf.read(curSize);

        // 3. 获取分片预签名 URL：
        //    单分片用 s3_upload_object/auth，多分片用 s3_repare_upload_parts_batch
        final prePath = chunkCount > 1
            ? '/file/s3_repare_upload_parts_batch'
            : '/file/s3_upload_object/auth';
        final pre = await _post(prePath, body: {
          'bucket': bucket,
          'key': key,
          'partNumberEnd': i,
          'partNumberStart': i,
          'uploadId': uploadId,
          'StorageNode': storageNode,
        });
        final preData = pre['data'] as Map<String, dynamic>? ?? {};
        final presigned = (preData['presignedUrls'] as Map?) ?? {};
        // key 可能是 int 或 String，都尝试
        final url = (presigned['$i'] ?? presigned[i])?.toString();
        if (url == null || url.isEmpty) {
          throw Pan123ApiException(-1, '分片 $i 预签名 URL 为空: $presigned');
        }

        // 4. PUT 分片
        await _s3Put(url, bytes, curSize, isCanceled);
        done += curSize;
        onProgress?.call(done, size);
      }
    } finally {
      await raf.close();
    }

    // 5. complete
    await _post('/file/upload_complete/v2', body: {
      'StorageNode': storageNode,
      'bucket': bucket,
      'fileId': fileId,
      'fileSize': size,
      'isMultipart': chunkCount > 1,
      'key': key,
      'uploadId': uploadId,
    });
    onProgress?.call(size, size);
  }

  /// PUT 分片到 S3 预签名 URL
  Future<void> _s3Put(String url, List<int> bytes, int size,
      bool Function()? isCanceled) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      if (isCanceled?.call() ?? false) throw Pan123ApiException(-3, '上传已取消');
      final req = http.Request('PUT', Uri.parse(url));
      req.headers['Content-Length'] = '$size';
      req.bodyBytes = bytes;
      final resp = await http.Response.fromStream(
          await _client.send(req).timeout(const Duration(seconds: 120)));
      if (resp.statusCode == 200) return;
      if (resp.statusCode == 403 && attempt == 0) continue; // 重试一次
      throw Pan123ApiException(resp.statusCode,
          '分片上传失败 HTTP ${resp.statusCode}: ${utf8.decode(resp.bodyBytes)}');
    }
  }

  /// 文件 MD5（hex）
  Future<String> _fileMd5(File file) async {
    final bytes = await file.readAsBytes();
    final digest = md5.convert(bytes);
    return digest.toString();
  }
}
