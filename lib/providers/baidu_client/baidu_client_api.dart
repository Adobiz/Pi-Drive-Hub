/// 百度网盘客户端协议 API 客户端。
///
/// 模拟百度网盘 PC 客户端，使用 BDUSS cookie 调用 rest/2.0/pcs 接口，
/// 可操作用户网盘任意目录。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'baidu_client_config.dart';
import 'baidu_client_auth.dart';
import 'cookie_jar.dart';

class BaiduClientApiException implements Exception {
  final int errno;
  final String message;

  BaiduClientApiException(this.errno, this.message);

  @override
  String toString() => 'BaiduClientApiException($errno): $message';
}

class BaiduClientApi {
  final BaiduClientAuthProvider auth;
  final CookieJar cookieJar;
  final http.Client _client;

  /// 下载并发数：普通账号 1（并发会被限速/封禁），SVIP 可调大
  /// 由 Provider 根据账号 vipType 自动设置
  int downloadConcurrency = 1;

  BaiduClientApi({required this.auth, http.Client? client})
      : cookieJar = auth.cookieJar,
        _client = client ?? http.Client();

  // ---------- 通用请求 ----------

  Map<String, String> _headers({bool json = false, Uri? forUri}) {
    final uri = forUri ?? Uri.parse(BaiduClientConfig.panBase);
    final cookieHeader = cookieJar.headerFor(uri);
    return {
      'User-Agent': BaiduClientConfig.ua,
      'Referer': '${BaiduClientConfig.panBase}/',
      if (json) 'Accept': 'application/json',
      if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
    };
  }

  Future<Map<String, dynamic>> _get(String url, {Map<String, String>? query}) async {
    var uri = Uri.parse(url);
    if (query != null) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }
    final resp = await _client
        .get(uri, headers: _headers(json: true, forUri: uri))
        .timeout(const Duration(seconds: 30));
    _absorb(resp);
    return _decode(resp);
  }

  /// 通用 form 提交（用于 filemanager 等）
  Future<Map<String, dynamic>> _postForm(
    String url, {
    Map<String, String>? query,
    Map<String, String>? body,
  }) async {
    var uri = Uri.parse(url);
    if (query != null) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }
    final resp = await _client
        .post(
          uri,
          headers: {..._headers(forUri: uri), 'Content-Type': 'application/x-www-form-urlencoded'},
          body: body,
        )
        .timeout(const Duration(seconds: 30));
    _absorb(resp);
    return _decode(resp);
  }

  void _absorb(http.Response resp) {
    final setCookie = resp.headers['set-cookie'];
    if (setCookie != null && setCookie.isNotEmpty) {
      cookieJar.setCookies([setCookie]);
    }
  }

  Map<String, dynamic> _decode(http.Response resp) {
    if (resp.statusCode != 200) {
      throw BaiduClientApiException(resp.statusCode, 'HTTP ${resp.statusCode}');
    }
    try {
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw BaiduClientApiException(-1, '响应解析失败');
    }
  }

  void _checkErrno(Map<String, dynamic> json) {
    final errno = json['errno'];
    if (errno == null || errno == 0) return;
    final msg = (json['errmsg'] ?? json['show_msg'] ?? 'errno=$errno').toString();
    throw BaiduClientApiException(errno is int ? errno : -1, msg);
  }

  String? _bdstokenCache;
  DateTime? _bdstokenTime;

  /// 获取 bdstoken（网页版写操作必需，缓存 10 分钟）
  Future<String> getBdstoken() async {
    if (_bdstokenCache != null &&
        _bdstokenTime != null &&
        DateTime.now().difference(_bdstokenTime!) < const Duration(minutes: 10)) {
      return _bdstokenCache!;
    }
    final json = await _get('${BaiduClientConfig.panBase}/api/gettemplatevariable', query: {
      'clienttype': '0',
      'app_id': BaiduClientConfig.appId,
      'fields': '["bdstoken"]',
    });
    _checkErrno(json);
    final token = (json['result'] as Map?)?['bdstoken'] as String?;
    if (token == null || token.isEmpty) {
      throw BaiduClientApiException(-1, '获取 bdstoken 失败');
    }
    _bdstokenCache = token;
    _bdstokenTime = DateTime.now();
    return token;
  }

  /// 网页版写操作公共查询参数（channel=chunlei&web=1 + bdstoken）
  Future<Map<String, String>> _webWriteQuery() async {
    final bdstoken = await getBdstoken();
    return {
      'channel': 'chunlei',
      'web': '1',
      'app_id': BaiduClientConfig.appId,
      'bdstoken': bdstoken,
      'clienttype': '0',
    };
  }

  // ---------- 用户信息 ----------

  /// 获取用户信息与配额
  Future<Map<String, dynamic>> getUserInfo() async {
    final json = await _get('${BaiduClientConfig.panBase}/api/quota');
    _checkErrno(json);
    return json;
  }

  /// 获取用户详细信息（昵称/头像/会员类型，uinfo 接口）
  Future<Map<String, dynamic>> getUserInfoDetail() async {
    final json = await _get('${BaiduClientConfig.panBase}/rest/2.0/xpan/nas', query: {
      'method': 'uinfo',
      'app_id': BaiduClientConfig.appId,
    });
    _checkErrno(json);
    return json;
  }

  // ---------- 文件列表 ----------

  Future<List<Map<String, dynamic>>> listDir(String path) async {
    // 注意：该 xpan 接口不接受 order 参数（会返回 errno=2），
    // 排序由上层在客户端本地完成
    final json = await _get('${BaiduClientConfig.panBase}/rest/2.0/xpan/file', query: {
      'method': 'list',
      'app_id': BaiduClientConfig.appId,
      'dir': path, // 注意：该接口用 dir 参数（path 会被忽略，永远返回根目录）
      'by': 'name',
    });
    _checkErrno(json);
    final list = (json['list'] as List?) ?? const [];
    return list.cast<Map<String, dynamic>>();
  }

  // ---------- 管理操作 ----------

  /// 搜索文件（按文件名，recursion=1 全盘递归）
  Future<List<Map<String, dynamic>>> search(String keyword) async {
    final json = await _get('${BaiduClientConfig.panBase}/rest/2.0/xpan/file', query: {
      'method': 'search',
      'app_id': BaiduClientConfig.appId,
      'key': keyword,
      'dir': '/',
      'recursion': '1',
    });
    _checkErrno(json);
    final list = (json['list'] as List?) ?? const [];
    return list.cast<Map<String, dynamic>>();
  }

  /// 创建目录（网页版 api/create，绕 9019 风控）
  Future<void> createFolder(String path) async {
    final json = await _postForm('${BaiduClientConfig.panBase}/api/create', query: {
      ...await _webWriteQuery(),
    }, body: {
      'path': path,
      'isdir': '1',
      'block_list': '[]',
      'tpl': 'chunlei',
    });
    _checkErrno(json);
  }

  /// 删除（网页版 api/filemanager）
  Future<void> delete(List<String> paths) async {
    final json = await _postForm('${BaiduClientConfig.panBase}/api/filemanager', query: {
      ...await _webWriteQuery(),
      'opera': 'delete',
      'async': '1',
      'onnest': 'fail',
    }, body: {
      'filelist': jsonEncode(paths),
    });
    _checkErrno(json);
  }

  /// 重命名（网页版 api/filemanager，opera=rename + newname）
  Future<void> rename(String from, String newName) async {
    final json = await _postForm('${BaiduClientConfig.panBase}/api/filemanager', query: {
      ...await _webWriteQuery(),
      'opera': 'rename',
      'async': '1',
      'onnest': 'fail',
    }, body: {
      'filelist': jsonEncode([
        {'path': from, 'newname': newName}
      ]),
    });
    _checkErrno(json);
  }

  /// 移动（网页版 api/filemanager，dest 为目标目录）
  Future<void> move(String from, String toDir) async {
    final json = await _postForm('${BaiduClientConfig.panBase}/api/filemanager', query: {
      ...await _webWriteQuery(),
      'opera': 'move',
      'async': '1',
      'onnest': 'fail',
    }, body: {
      'filelist': jsonEncode([
        {'path': from, 'dest': toDir}
      ]),
    });
    _checkErrno(json);
  }

  // ---------- 上传 ----------

  /// 获取上传分片域名
  Future<String> locateUploadHost() async {
    final json = await _get('${BaiduClientConfig.pcsFileBase}/rest/2.0/pcs/file', query: {
      'method': 'locateupload',
      'app_id': BaiduClientConfig.appId,
      'upload_version': '2.0',
    });
    _checkErrno(json);
    final servers = (json['servers'] as List?) ?? const [];
    for (final s in servers) {
      final server = (s as Map<String, dynamic>)['server'] as String?;
      if (server != null && server.startsWith('https://')) {
        return server;
      }
    }
    throw BaiduClientApiException(-1, '获取上传域名失败');
  }

  /// 分片上传文件到任意目录
  Future<void> upload(String remotePath, List<int> bytes, {void Function(int, int?)? onProgress}) async {
    final size = bytes.length;
    if (size == 0) throw BaiduClientApiException(-1, '空文件不支持');

    // 1. 计算各分片 MD5
    final blockList = <String>[];
    for (var offset = 0; offset < size; offset += BaiduClientConfig.blockSize) {
      final end = (offset + BaiduClientConfig.blockSize > size) ? size : offset + BaiduClientConfig.blockSize;
      final block = bytes.sublist(offset, end);
      blockList.add(md5.convert(block).toString());
    }
    final contentMd5 = md5.convert(bytes).toString();

    // 2. precreate
    final pre = await _postForm('${BaiduClientConfig.panBase}/api/precreate', body: {
      'path': remotePath,
      'size': '$size',
      'isdir': '0',
      'block_list': jsonEncode(blockList),
      'autoinit': '1',
      'content-md5': contentMd5,
      'rtype': '2',
    });
    _checkErrno(pre);

    // 秒传命中则直接成功
    if ((pre['return_type'] as num?) == 3) {
      onProgress?.call(size, size);
      return;
    }

    final uploadId = pre['uploadid'] as String?;
    if (uploadId == null) throw BaiduClientApiException(-1, 'precreate 未返回 uploadid');

    final blockListResp = (pre['block_list'] as List?)?.cast<num>() ?? [];
    final host = await locateUploadHost();

    // 3. 上传缺失的分片
    var done = 0;
    for (final partseq in blockListResp) {
      final seq = partseq.toInt();
      final offset = seq * BaiduClientConfig.blockSize;
      final end = (offset + BaiduClientConfig.blockSize > size) ? size : offset + BaiduClientConfig.blockSize;
      final block = bytes.sublist(offset, end);

      final uri = Uri.parse('$host/rest/2.0/pcs/superfile2').replace(queryParameters: {
        'method': 'upload',
        'app_id': BaiduClientConfig.appId,
        'type': 'tmpfile',
        'path': remotePath,
        'uploadid': uploadId,
        'partseq': '$seq',
        'partoffset': '$offset',
      });
      final req = http.MultipartRequest('POST', uri);
      req.headers.addAll(_headers());
      req.files.add(http.MultipartFile.fromBytes('file', block, filename: 'block'));
      final streamed = await _client
          .send(req)
          .timeout(const Duration(seconds: 120));
      final resp = await http.Response.fromStream(streamed);
      _absorb(resp);
      final json = _decode(resp);
      _checkErrno(json);
      done += block.length;
      onProgress?.call(done, size);
    }

    // 4. create 合并
    final create = await _postForm('${BaiduClientConfig.panBase}/api/create', body: {
      'uploadid': uploadId,
      'path': remotePath,
      'size': '$size',
      'isdir': '0',
      'rtype': '2',
      'block_list': jsonEncode(blockList),
    });
    _checkErrno(create);
    onProgress?.call(size, size);
  }

  // ---------- 下载 ----------

  /// 获取用户 uid（下载签名需要）
  Future<int> getUid() async {
    final json = await _get('${BaiduClientConfig.panBase}/rest/2.0/xpan/nas', query: {
      'method': 'uinfo',
      'app_id': BaiduClientConfig.appId,
    });
    final uid = (json['uk'] as num?)?.toInt();
    if (uid == null) throw BaiduClientApiException(-1, '获取 uid 失败');
    return uid;
  }

  /// 获取下载直链（locatedownload + 签名）
  Future<String> locateDownload(String remotePath) async {
    final bduss = cookieJar.get('BDUSS') ?? '';
    final time = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final devuid = _devUid(bduss);
    final uid = await getUid();
    final rand = _locateRand(time, devuid, bduss, uid);

    final query = <String, String>{
      'ant': '1',
      'check_blue': '1',
      'es': '1',
      'esl': '1',
      'app_id': BaiduClientConfig.appId,
      'method': 'locatedownload',
      'path': remotePath,
      'ver': '4.0',
      'clienttype': '17',
      'channel': '0',
      'apn_id': '1_0',
      'freeisp': '0',
      'queryfree': '0',
      'use': '0',
      'time': '$time',
      'rand': rand,
      'devuid': devuid,
      'cuid': devuid,
    };
    final json = await _get('${BaiduClientConfig.pcsFileBase}/rest/2.0/pcs/file', query: query);
    _checkErrno(json);

    final urls = (json['urls'] as List?) ?? const [];
    for (final u in urls) {
      final item = u as Map<String, dynamic>;
      if ((item['encrypt'] as num?) == 0) {
        final url = item['url'] as String?;
        if (url != null && url.startsWith('http')) return url;
      }
    }
    throw BaiduClientApiException(-1, '未找到下载直链');
  }

  /// devuid = MD5(bduss) 大写 + "|0"
  String _devUid(String bduss) {
    final digest = md5.convert(utf8.encode(bduss)).toString().toUpperCase();
    return '$digest|0';
  }

  /// rand = SHA1(SHA1(bduss).hex + uid + 固定串 + time + devuid)
  String _locateRand(int time, String devuid, String bduss, int uid) {
    const fixed = 'ebrcUYiuxaZv2XGu7KIYKxUrqfnOfpDF';
    final sha1Bduss = sha1.convert(utf8.encode(bduss)).toString();
    final digest = sha1.convert(utf8.encode('$sha1Bduss$uid$fixed$time$devuid'));
    return digest.toString();
  }

  /// 下载文件到本地（SVIP 并发分片加速，实时进度）
  ///
  /// 百度下载直链（dlink）要求携带会话 cookie 且不能带 Referer，
  /// 否则返回 403（BaiduPCS-Go 同款处理）。
  /// 普通账号并发会被限速/封禁，仅 SVIP 开启并发。
  Future<void> download(String remotePath, String localPath,
      {void Function(int, int?)? onProgress,
      bool Function()? isCanceled,
      Set<int>? completedBlocks,
      void Function(int, Set<int>)? onBlocks}) async {
    final url = await locateDownload(remotePath);
    final uri = Uri.parse(url);
    final cookieHeader = cookieJar.headerFor(uri);
    final file = File(localPath);

    // 1. 首检：获取文件总大小（x-bs-file-size 或 Content-Range）
    final headReq = http.Request('GET', uri);
    headReq.headers['User-Agent'] = BaiduClientConfig.ua;
    if (cookieHeader.isNotEmpty) headReq.headers['Cookie'] = cookieHeader;
    headReq.headers['Range'] = 'bytes=0-0';
    final headResp = await http.Response.fromStream(
      await _client.send(headReq).timeout(const Duration(seconds: 30)),
    );
    int? total;
    if (headResp.statusCode == 200 || headResp.statusCode == 206) {
      final bs = headResp.headers['x-bs-file-size'];
      if (bs != null) {
        total = int.tryParse(bs);
      } else {
        final cr = headResp.headers['content-range'];
        if (cr != null) {
          final slash = cr.lastIndexOf('/');
          if (slash >= 0) total = int.tryParse(cr.substring(slash + 1));
        }
      }
    }

    // 2. 并发分片下载。
    //    分片大小按文件大小适配（见 _selectChunkSize）：小文件 256KB，
    //    中等 512KB，大文件 1MB。较小分片让断点续传粒度更细——
    //    暂停时更容易留下已完成分片，避免"断了就从头重下"。
    final chunkSize = _selectChunkSize(total);
    final concurrency = downloadConcurrency;
    if (total == null || total <= chunkSize) {
      // 小文件或未知大小：串行单块下载
      final req = http.Request('GET', uri);
      req.headers['User-Agent'] = BaiduClientConfig.ua;
      if (cookieHeader.isNotEmpty) req.headers['Cookie'] = cookieHeader;
      req.headers['Range'] = 'bytes=0-';
      final resp = await http.Response.fromStream(
        await _client.send(req).timeout(const Duration(seconds: 120)),
      );
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw BaiduClientApiException(resp.statusCode, '下载 HTTP ${resp.statusCode}');
      }
      await file.writeAsBytes(resp.bodyBytes, flush: true);
      onProgress?.call(resp.bodyBytes.length, resp.bodyBytes.length);
      return;
    }

    // 计算分块数（此处 total 已确认非 null）
    final fileSize = total;
    final blockCount = (fileSize + chunkSize - 1) ~/ chunkSize;
    // 断点续传：记录已完成分片
    final doneBlocks = completedBlocks ?? <int>{};
    var nextBlock = 0;
    // 关键：断点续传时用不截断模式打开（write 会清空已下载数据！），
    // 全新下载才用 write 截断
    final raf = await file.open(
      mode: doneBlocks.isEmpty ? FileMode.write : FileMode.writeOnlyAppend,
    );
    try {
      await raf.truncate(total);
      var completed = doneBlocks.length * chunkSize;
      onProgress?.call(completed, total);
      final errors = <Object>[];

      Future<void> worker() async {
        while (true) {
          if (isCanceled?.call() ?? false) {
            throw BaiduClientApiException(-3, '下载已取消');
          }
          final blockIndex = nextBlock++;
          if (blockIndex >= blockCount) return;
          // 跳过已完成的分片（断点续传）
          if (doneBlocks.contains(blockIndex)) continue;
          final start = blockIndex * chunkSize;
          final end = min(start + chunkSize, fileSize) - 1;
          try {
            // 流式下载分片：分片内部按数据块刷新进度（更平滑）
            final bytes = await _downloadChunkWithRetry(
              uri, cookieHeader, start, end, isCanceled,
              onChunkProgress: (chunkBytes) {
                completed += chunkBytes;
                onProgress?.call(completed, total);
              },
            );
            await raf.setPosition(start);
            await raf.writeFrom(bytes);
            doneBlocks.add(blockIndex);
            onBlocks?.call(completed, doneBlocks);
          } catch (e) {
            errors.add(e);
            return;
          }
        }
      }

      await Future.wait(List.generate(concurrency, (_) => worker()));
      if (errors.isNotEmpty) {
        throw errors.first;
      }
      await raf.flush();
    } finally {
      await raf.close();
    }
    onProgress?.call(total, total);
  }

  /// 根据文件总大小选择分片大小（断点续传粒度 + 百度分片上限平衡）
  int _selectChunkSize(int? totalBytes) {
    if (totalBytes == null || totalBytes <= 0) {
      return 1 * 1024 * 1024;
    }
    if (totalBytes < 10 * 1024 * 1024) {
      return 256 * 1024; // <10MB：256KB 分片
    }
    if (totalBytes < 50 * 1024 * 1024) {
      return 512 * 1024; // 10~50MB：512KB 分片
    }
    return 1 * 1024 * 1024; // >50MB：1MB 分片
  }

  /// 下载单个分片：流式读取 + 超时 + 自动重试（最多 3 次）。
  ///
  /// 通过 [onChunkProgress] 在分片内部按数据块实时上报进度，
  /// 让下载进度条更平滑（而不是按 4MB 分片整块跳）。
  Future<Uint8List> _downloadChunkWithRetry(
    Uri uri,
    String cookieHeader,
    int start,
    int end,
    bool Function()? isCanceled, {
    void Function(int chunkBytes)? onChunkProgress,
  }) async {
    const maxAttempts = 3;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (isCanceled?.call() ?? false) {
        throw BaiduClientApiException(-3, '下载已取消');
      }
      try {
        final req = http.Request('GET', uri);
        req.headers['User-Agent'] = BaiduClientConfig.ua;
        if (cookieHeader.isNotEmpty) req.headers['Cookie'] = cookieHeader;
        req.headers['Range'] = 'bytes=$start-$end';
        final streamed = await _client
            .send(req)
            .timeout(const Duration(seconds: 60));
        if (streamed.statusCode != 200 && streamed.statusCode != 206) {
          throw BaiduClientApiException(streamed.statusCode,
              '下载分片 HTTP ${streamed.statusCode} @ $start');
        }
        // 流式收集 + 实时进度。
        // 逐块检查取消：暂停时旧线程立即中断退出（当前分片丢弃，
        // 但已完整下载的分片仍保留在 doneBlocks，断点续传不受影响），
        // 避免新旧线程并发写同一文件。
        final builder = BytesBuilder(copy: false);
        await for (final chunk in streamed.stream) {
          if (isCanceled?.call() ?? false) {
            throw BaiduClientApiException(-3, '下载已取消');
          }
          builder.add(chunk);
          onChunkProgress?.call(chunk.length);
        }
        return builder.takeBytes();
      } catch (e) {
        if (attempt == maxAttempts - 1) {
          rethrow; // 最后一次失败直接抛出
        }
        // 短暂等待后重试
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    throw BaiduClientApiException(-1, '下载分片失败');
  }
}
