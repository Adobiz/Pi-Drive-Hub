/// 夸克网盘 API 客户端。
///
/// 请求带 cookie + Electron UA，域名 drive.quark.cn/1/clouddrive。
/// 上传走阿里云 OSS 分片流程（pre → auth → put 分片 → commit → finish）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'quark_auth.dart';
import 'quark_config.dart';

class QuarkApiException implements Exception {
  final int code;
  final String message;

  QuarkApiException(this.code, this.message);

  @override
  String toString() => 'QuarkApiException($code): $message';
}

class QuarkApi {
  final QuarkAuthProvider auth;
  final http.Client _client;

  QuarkApi({required this.auth, http.Client? client})
      : _client = client ?? http.Client();

  // ---------- 通用请求 ----------

  Map<String, String> _headers({Uri? forUri}) {
    final uri = forUri ?? Uri.parse(QuarkConfig.homeBase);
    return {
      'Cookie': auth.cookieJar.headerFor(uri),
      'Accept': 'application/json, text/plain, */*',
      'Referer': '${QuarkConfig.homeBase}/',
      'User-Agent': QuarkConfig.ua,
    };
  }

  Future<Map<String, dynamic>> _get(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('${QuarkConfig.driveBase}$path').replace(
      queryParameters: {'pr': 'ucpro', 'fr': 'pc', ...?query},
    );
    final resp = await _client
        .get(uri, headers: _headers(forUri: uri))
        .timeout(const Duration(seconds: 30));
    _absorb(resp);
    return _decode(resp);
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('${QuarkConfig.driveBase}$path').replace(
      queryParameters: {'pr': 'ucpro', 'fr': 'pc', ...?query},
    );
    final resp = await _client
        .post(
          uri,
          headers: {
            ..._headers(forUri: uri),
            'Content-Type': 'application/json',
          },
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    _absorb(resp);
    return _decode(resp);
  }

  void _absorb(http.Response resp) {
    final setCookie = resp.headers['set-cookie'];
    if (setCookie != null && setCookie.isNotEmpty) {
      auth.cookieJar.setCookies([setCookie]);
    }
  }

  Map<String, dynamic> _decode(http.Response resp) {
    if (resp.statusCode != 200) {
      // 尝试从响应体解析真实错误信息（如容量限制），便于定位
      String detail = 'HTTP ${resp.statusCode}';
      try {
        final body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final msg = body['message']?.toString();
        if (msg != null && msg.isNotEmpty) detail = msg;
      } catch (_) {}
      throw QuarkApiException(resp.statusCode, detail);
    }
    try {
      final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final code = (json['code'] as num?)?.toInt() ?? 0;
      if (code != 0) {
        throw QuarkApiException(code, (json['message'] ?? 'code=$code').toString());
      }
      return json;
    } catch (e) {
      if (e is QuarkApiException) rethrow;
      throw QuarkApiException(-1, '响应解析失败: $e');
    }
  }

  // ---------- 用户信息 ----------

  /// 获取容量与会员信息
  ///
  /// 网页版真实接口：GET drive-pc.quark.cn/1/clouddrive/member
  /// （fetch_subscribe/_ch/fetch_identity），可带 x-clouddrive-st 头。
  Future<Map<String, dynamic>?> getCapacityInfo() async {
    try {
      // 网页版 member 接口（真接口），无 st 先试
      final uri = Uri.parse('https://drive-pc.quark.cn/1/clouddrive/member')
          .replace(queryParameters: {
        'fetch_subscribe': 'true',
        '_ch': 'home',
        'fetch_identity': 'true',
        'pr': 'ucpro',
        'fr': 'pc',
      });
      final resp = await _client
          .get(uri, headers: _headers(forUri: uri))
          .timeout(const Duration(seconds: 30));
      _absorb(resp);
      if (resp.statusCode == 200) {
        final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        if (json['code'] == 0) {
          final data = json['data'] as Map<String, dynamic>?;
          if (data != null && data.isNotEmpty) {
            return data;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> getUserInfo() async {
    final uri = Uri.parse(QuarkConfig.accountBase)
        .replace(queryParameters: {'fr': 'pc', 'platform': 'pc'});
    final resp = await _client
        .get(uri, headers: _headers(forUri: uri))
        .timeout(const Duration(seconds: 30));
    _absorb(resp);
    final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final data = json['data'];
    if (data == null) throw QuarkApiException(-1, '获取用户信息失败');
    return data as Map<String, dynamic>;
  }

  // ---------- 文件列表 ----------

  /// 列出目录（分页拉全）
  Future<List<Map<String, dynamic>>> listDir(String pdirFid, {int pageSize = 50}) async {
    final all = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final json = await _get('/file/sort', query: {
        'pdir_fid': pdirFid,
        '_page': '$page',
        '_size': '$pageSize',
        '_fetch_total': '1',
        '_fetch_sub_dirs': '0',
        '_sort': 'file_type:asc,updated_at:desc',
        '_fetch_full_path': '0',
        'fetch_all_file': '1',
      });
      final data = json['data'] as Map<String, dynamic>?;
      final list = (data?['list'] as List?) ?? const [];
      all.addAll(list.cast<Map<String, dynamic>>());
      final total = ((json['metadata'] as Map?)?['_total'] as num?)?.toInt() ?? 0;
      if (all.length >= total || list.isEmpty) break;
      page++;
    }
    return all;
  }

  // ---------- 文件操作 ----------

  /// 新建目录（dir_path 是完整路径，如 /a/b 会递归创建）
  Future<void> createFolder(String dirPath) async {
    await _post('/file', body: {
      'pdir_fid': '0',
      'file_name': '',
      'dir_path': dirPath,
      'dir_init_lock': false,
    });
  }

  /// 重命名
  Future<void> rename(String fid, String newName) async {
    await _post('/file/rename', body: {
      'fid': fid,
      'file_name': newName,
    });
  }

  /// 删除（filelist 为 fid 列表）
  Future<void> delete(List<String> fids) async {
    await _post('/file/delete', body: {
      'action_type': 2,
      'filelist': fids,
      'exclude_fids': <String>[],
    });
  }

  /// 移动（toPdirFid 为目标目录 fid）
  Future<void> move(List<String> fids, String toPdirFid) async {
    await _post('/file/move', body: {
      'filelist': fids,
      'to_pdir_fid': toPdirFid,
      'exclude_fids': <String>[],
      'action_type': 1,
    });
  }

  // ---------- 下载 ----------

  /// 获取下载直链（返回 download_url）
  Future<String> getDownloadUrl(String fid) async {
    final json = await _post('/file/download', body: {'fids': [fid]});
    final data = json['data'] as List?;
    if (data == null || data.isEmpty) throw QuarkApiException(-1, '获取下载链接失败');
    final url = (data.first as Map<String, dynamic>)['download_url'] as String?;
    if (url == null) throw QuarkApiException(-1, '下载链接为空');
    return url;
  }

  /// 下载文件到本地（带 cookie/Referer + Range 分片 + 断点续传）
  ///
  /// 夸克下载直链要求：携带会话 cookie + Referer: pan.quark.cn，
  /// 并按 Range 分片请求（每次 10MB），否则返回 403。
  /// [completedBlocks] 记录已完成分片，续传时跳过。
  Future<void> download(String fid, String localPath,
      {void Function(int, int?)? onProgress,
      bool Function()? isCanceled,
      Set<int>? completedBlocks,
      void Function(int, Set<int>)? onBlocks}) async {
    final url = await getDownloadUrl(fid);
    final uri = Uri.parse(url);
    final cookieHeader = auth.cookieJar.headerFor(uri);
    final file = File(localPath);
    final hasResume = (completedBlocks?.isNotEmpty ?? false);
    // 有断点时预创建文件（不截断已有数据）
    if (hasResume && !file.existsSync()) {
      await file.create(recursive: true);
    }

    // 首检：获取文件大小
    final headReq = http.Request('GET', uri);
    headReq.headers.addAll({
      'User-Agent': QuarkConfig.ua,
      'Referer': '${QuarkConfig.homeBase}/',
      if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
      'Range': 'bytes=0-0',
    });
    final headResp = await http.Response.fromStream(
      await _client.send(headReq).timeout(const Duration(seconds: 30)),
    );
    int? total;
    if (headResp.statusCode == 200 || headResp.statusCode == 206) {
      final cr = headResp.headers['content-range'];
      if (cr != null) {
        final slash = cr.lastIndexOf('/');
        if (slash >= 0) total = int.tryParse(cr.substring(slash + 1));
      }
    }

    // 分片下载（1MB/块，小分片让断点续传粒度细，
    // 暂停时更容易留下已完成分片，避免从头重下）+ 断点续传
    const chunkSize = 1 * 1024 * 1024;
    final doneBlocks = completedBlocks ?? <int>{};
    // 关键：续传时用不截断模式打开（write 会清空已下载数据！），
    // 配合 RandomAccessFile.setPosition 定位写入，保留已完成分片
    final raf = await file.open(
      mode: doneBlocks.isEmpty ? FileMode.write : FileMode.writeOnlyAppend,
    );
    var received = 0;
    var start = 0;
    try {
      if (total != null) await raf.truncate(total);
      while (true) {
        if (isCanceled?.call() ?? false) throw QuarkApiException(-3, '下载已取消');
        final blockIndex = start ~/ chunkSize;
        // 跳过已完成分片（断点续传），保留已写入数据
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
        final req = http.Request('GET', uri);
        req.headers.addAll({
          'User-Agent': QuarkConfig.ua,
          'Referer': '${QuarkConfig.homeBase}/',
          if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
          'Range': end != null ? 'bytes=$start-$end' : 'bytes=$start-',
        });
        final streamed = await _client
            .send(req)
            .timeout(const Duration(seconds: 60));
        if (streamed.statusCode != 200 && streamed.statusCode != 206) {
          throw QuarkApiException(streamed.statusCode,
              '下载分片 HTTP ${streamed.statusCode} @ $start');
        }
        // 流式读取：分片内部按数据块实时上报进度 + 定位写入
        var chunkBytes = 0;
        await raf.setPosition(start);
        await for (final chunk in streamed.stream) {
          if (isCanceled?.call() ?? false) {
            throw QuarkApiException(-3, '下载已取消');
          }
          await raf.writeFrom(chunk);
          chunkBytes += chunk.length;
          received += chunk.length;
          onProgress?.call(received, total);
        }
        if (chunkBytes == 0) break;
        doneBlocks.add(blockIndex);
        onBlocks?.call(received, doneBlocks);
        if (end == null) break;
        if (chunkBytes < chunkSize) break;
        start += chunkSize;
      }
      await raf.flush();
    } finally {
      await raf.close();
    }
    onProgress?.call(received, total);
  }

  // ---------- 上传（阿里云 OSS 分片） ----------

  /// 分片大小（由 pre 返回，默认 32MB）
  int _partSize = 32 * 1024 * 1024;

  Future<void> upload(String localPath, String pdirFid, String fileName,
      {void Function(int, int?)? onProgress,
      bool Function()? isCanceled}) async {
    final file = File(localPath);
    final size = await file.length();
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. pre：创建上传会话
    final pre = await _post('/file/upload/pre', body: {
      'ccp_hash_update': true,
      'dir_name': '',
      'file_name': fileName,
      'format_type': 'application/octet-stream',
      'l_created_at': now,
      'l_updated_at': now,
      'pdir_fid': pdirFid,
      'size': size,
    });
    final preData = pre['data'] as Map<String, dynamic>;
    final partSize = ((pre['metadata'] as Map?)?['part_size'] as num?)?.toInt();
    if (partSize != null && partSize > 0) _partSize = partSize;
    final taskId = preData['task_id'] as String;
    final uploadId = preData['upload_id'] as String;
    final objKey = preData['obj_key'] as String;
    final uploadUrl = preData['upload_url'] as String;
    final bucket = preData['bucket'] as String;
    final authInfo = preData['auth_info'] as String;
    final callback = preData['callback'];

    // 2. 计算 MD5/SHA1 做秒传检测
    final bytes = await file.readAsBytes();
    final md5hex = md5.convert(bytes).toString();
    final sha1hex = sha1.convert(bytes).toString();
    final hash = await _post('/file/update/hash', body: {
      'md5': md5hex,
      'sha1': sha1hex,
      'task_id': taskId,
    });
    final hashData = hash['data'] as Map<String, dynamic>?;
    if (hashData?['finish'] == true) {
      onProgress?.call(size, size); // 秒传命中
      return;
    }

    // 3. 分片上传
    final etags = <String>[];
    var offset = 0;
    var partNumber = 1;
    while (offset < size) {
      if (isCanceled?.call() ?? false) throw QuarkApiException(-3, '上传已取消');
      final end = min(offset + _partSize, size);
      final partBytes = bytes.sublist(offset, end);
      final etag = await _uploadPart(
        authInfo, taskId, bucket, uploadUrl, objKey, uploadId,
        partNumber, partBytes,
      );
      etags.add(etag);
      offset = end;
      partNumber++;
      onProgress?.call(offset, size);
    }

    // 4. commit 合并
    await _uploadCommit(
      authInfo, taskId, bucket, uploadUrl, objKey, uploadId, callback, etags,
    );

    // 5. finish 完成
    await _post('/file/upload/finish', body: {
      'obj_key': objKey,
      'task_id': taskId,
    });
    onProgress?.call(size, size);
  }

  /// 上传单个分片到 OSS
  Future<String> _uploadPart(
    String authInfo,
    String taskId,
    String bucket,
    String uploadUrl,
    String objKey,
    String uploadId,
    int partNumber,
    List<int> bytes,
  ) async {
    final timeStr = _ossDate();
    const contentType = 'application/octet-stream';
    final authMeta = 'PUT\n\n$contentType\n$timeStr\nx-oss-date:$timeStr\nx-oss-user-agent:aliyun-sdk-js/6.6.1 Chrome 98.0.4758.80 on Windows 10 64-bit\n/$bucket/$objKey?partNumber=$partNumber&uploadId=$uploadId';
    final auth = await _post('/file/upload/auth', body: {
      'auth_info': authInfo,
      'auth_meta': authMeta,
      'task_id': taskId,
    });
    final authKey = ((auth['data'] as Map<String, dynamic>?)?['auth_key']) as String?;
    if (authKey == null) throw QuarkApiException(-1, '获取分片签名失败');

    final host = uploadUrl.replaceFirst(RegExp(r'^https?://'), '');
    final uri = Uri.parse('https://$bucket.$host/$objKey').replace(
      queryParameters: {'partNumber': '$partNumber', 'uploadId': uploadId},
    );
    final req = http.Request('PUT', uri);
    req.headers.addAll({
      'Authorization': authKey,
      'Content-Type': 'application/octet-stream',
      'Referer': '${QuarkConfig.homeBase}/',
      'x-oss-date': timeStr,
      'x-oss-user-agent': 'aliyun-sdk-js/6.6.1 Chrome 98.0.4758.80 on Windows 10 64-bit',
    });
    req.bodyBytes = bytes;
    final resp = await http.Response.fromStream(await _client.send(req));
    if (resp.statusCode != 200) {
      throw QuarkApiException(resp.statusCode, '分片上传失败 HTTP ${resp.statusCode}: ${utf8.decode(resp.bodyBytes)}');
    }
    final etag = resp.headers['etag'];
    if (etag == null) throw QuarkApiException(-1, '分片上传未返回 ETag');
    return etag;
  }

  /// 合并分片（CompleteMultipartUpload）
  Future<void> _uploadCommit(
    String authInfo,
    String taskId,
    String bucket,
    String uploadUrl,
    String objKey,
    String uploadId,
    dynamic callback,
    List<String> etags,
  ) async {
    final buf = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8"?>\n<CompleteMultipartUpload>\n');
    for (var i = 0; i < etags.length; i++) {
      buf.write('<Part>\n<PartNumber>${i + 1}</PartNumber>\n<ETag>${etags[i]}</ETag>\n</Part>\n');
    }
    buf.write('</CompleteMultipartUpload>');
    final xmlBody = buf.toString();
    final contentMd5 = base64Encode(md5.convert(utf8.encode(xmlBody)).bytes);
    final callbackBase64 = base64Encode(utf8.encode(jsonEncode(callback ?? {})));

    final timeStr = _ossDate();
    // 注意：Dart http 发送字符串 body 时 Content-Type 会自动追加 ; charset=utf-8，
    // OSS 签名按实际请求的 Content-Type 计算，故这里必须写全
    const xmlContentType = 'application/xml; charset=utf-8';
    final authMeta = 'POST\n$contentMd5\n$xmlContentType\n$timeStr\nx-oss-callback:$callbackBase64\nx-oss-date:$timeStr\nx-oss-user-agent:aliyun-sdk-js/6.6.1 Chrome 98.0.4758.80 on Windows 10 64-bit\n/$bucket/$objKey?uploadId=$uploadId';
    final auth = await _post('/file/upload/auth', body: {
      'auth_info': authInfo,
      'auth_meta': authMeta,
      'task_id': taskId,
    });
    final authKey = ((auth['data'] as Map<String, dynamic>?)?['auth_key']) as String?;
    if (authKey == null) throw QuarkApiException(-1, '获取合并签名失败');

    final host = uploadUrl.replaceFirst(RegExp(r'^https?://'), '');
    final uri = Uri.parse('https://$bucket.$host/$objKey')
        .replace(queryParameters: {'uploadId': uploadId});
    final req = http.Request('POST', uri);
    req.headers.addAll({
      'Authorization': authKey,
      'Content-MD5': contentMd5,
      'Content-Type': xmlContentType,
      'Referer': '${QuarkConfig.homeBase}/',
      'x-oss-callback': callbackBase64,
      'x-oss-date': timeStr,
      'x-oss-user-agent': 'aliyun-sdk-js/6.6.1 Chrome 98.0.4758.80 on Windows 10 64-bit',
    });
    req.body = xmlBody;
    final resp = await http.Response.fromStream(await _client.send(req));
    if (resp.statusCode != 200) {
      throw QuarkApiException(resp.statusCode, '合并分片失败 HTTP ${resp.statusCode}: ${utf8.decode(resp.bodyBytes)}');
    }
  }

  /// OSS 日期头（GMT）
  String _ossDate() {
    final now = DateTime.now().toUtc();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final day = now.day.toString().padLeft(2, '0');
    return '${now.weekday == 7 ? "Sun" : const ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][now.weekday - 1]}, $day ${months[now.month - 1]} ${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} GMT';
  }
}
