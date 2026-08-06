/// 简易 Cookie 容器：保存/读取 Set-Cookie，并组装 Cookie 头。
library;

class Cookie {
  final String name;
  final String value;
  final String? domain;

  Cookie(this.name, this.value, {this.domain});

  @override
  String toString() => '$name=$value';
}

class CookieJar {
  final Map<String, Cookie> _cookies = {};

  /// 解析响应头里的 Set-Cookie，全部保存
  void setCookies(List<String> setCookieHeaders) {
    for (final header in setCookieHeaders) {
      final parts = header.split(';');
      final first = parts.first.trim();
      final eq = first.indexOf('=');
      if (eq <= 0) continue;
      final name = first.substring(0, eq).trim();
      final value = first.substring(eq + 1).trim();
      String? domain;
      for (final part in parts.skip(1)) {
        final t = part.trim();
        if (t.toLowerCase().startsWith('domain=')) {
          domain = t.substring(7);
        }
      }
      if (value.isEmpty || value == 'DEL') {
        _cookies.remove(name);
      } else {
        _cookies[name] = Cookie(name, value, domain: domain);
      }
    }
  }

  /// 手动设置 cookie（登录成功后保存 BDUSS 等）
  void set(String name, String value, {String? domain}) {
    _cookies[name] = Cookie(name, value, domain: domain);
  }

  /// 组装 Cookie 请求头
  String headerFor(Uri uri) {
    final host = uri.host;
    final values = <String>[];
    _cookies.forEach((name, cookie) {
      // 简化：domain 为空或 host 包含 domain 后缀才发送
      if (cookie.domain == null || host == cookie.domain || host.endsWith('.${cookie.domain}')) {
        values.add('$name=${cookie.value}');
      }
    });
    return values.join('; ');
  }

  String? get(String name) => _cookies[name]?.value;

  Map<String, String> toMap() => {for (final e in _cookies.entries) e.key: e.value.value};

  void loadMap(Map<String, String> map) {
    map.forEach((k, v) => _cookies[k] = Cookie(k, v));
  }

  void clear() => _cookies.clear();
}
