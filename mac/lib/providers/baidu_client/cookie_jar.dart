import 'dart:io' as io;

class Cookie {
  final String name;
  final String value;
  final String? domain;
  final String path;
  final bool secure;
  final bool hostOnly;
  final DateTime? expires;
  Cookie(
    this.name,
    this.value, {
    this.domain,
    this.path = '/',
    this.secure = true,
    this.hostOnly = false,
    this.expires,
  });
}

/// Cookies always have a service scope. Legacy credentials migrate to that
/// scope; a jar without an origin never emits unscoped credentials.
class CookieJar {
  final Uri? origin;
  final Map<String, Cookie> _cookies = {};
  CookieJar({this.origin});
  String _key(Cookie c) => '${c.name}|${c.domain}|${c.path}';
  String? _domain(String? value) =>
      value?.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
  bool _within(String host, String domain) =>
      host == domain || host.endsWith('.$domain');
  bool _trusted(String domain) =>
      origin != null && _within(domain, origin!.host);

  void setCookies(List<String> headers, {Uri? responseOrigin}) {
    final source = responseOrigin ?? origin;
    if (source == null || source.scheme != 'https' || !_trusted(source.host)) {
      return;
    }
    for (final header in headers) {
      try {
        final parsed = io.Cookie.fromSetCookieValue(header);
        final domain = _domain(parsed.domain) ?? source.host;
        if (!_trusted(domain) || !_within(source.host, domain)) continue;
        final cookie = Cookie(
          parsed.name,
          parsed.value,
          domain: domain,
          path: parsed.path ?? '/',
          secure: true,
          hostOnly: parsed.domain == null,
          expires:
              parsed.maxAge != null
                  ? DateTime.now().add(Duration(seconds: parsed.maxAge!))
                  : parsed.expires,
        );
        if (parsed.value.isEmpty ||
            parsed.value == 'DEL' ||
            (cookie.expires?.isBefore(DateTime.now()) ?? false)) {
          _cookies.remove(_key(cookie));
        } else {
          _cookies[_key(cookie)] = cookie;
        }
      } on FormatException {
        // Ignore malformed server cookies rather than widening their scope.
      }
    }
  }

  void set(String name, String value, {String? domain}) {
    final scope = _domain(domain) ?? origin?.host;
    if (scope == null || !_trusted(scope)) return;
    final cookie = Cookie(name, value, domain: scope);
    _cookies[_key(cookie)] = cookie;
  }

  String headerFor(Uri uri) {
    if (uri.scheme != 'https') return '';
    final path = uri.path.isEmpty ? '/' : uri.path;
    final values =
        _cookies.values.where((cookie) {
            final domain = cookie.domain;
            if (domain == null || !_trusted(domain)) return false;
            if (cookie.expires?.isBefore(DateTime.now()) ?? false) return false;
            if (cookie.hostOnly
                ? uri.host != domain
                : !_within(uri.host, domain)) {
              return false;
            }
            return path == cookie.path ||
                (path.startsWith(cookie.path) &&
                    (cookie.path.endsWith('/') ||
                        path.substring(cookie.path.length).startsWith('/')));
          }).toList()
          ..sort((a, b) => b.path.length.compareTo(a.path.length));
    return values.map((c) => '${c.name}=${c.value}').join('; ');
  }

  String? get(String name) {
    for (final c in _cookies.values) {
      if (c.name == name && !(c.expires?.isBefore(DateTime.now()) ?? false)) {
        return c.value;
      }
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
    'version': 2,
    'cookies':
        _cookies.values
            .map(
              (c) => {
                'name': c.name,
                'value': c.value,
                'domain': c.domain,
                'path': c.path,
                'secure': c.secure,
                'hostOnly': c.hostOnly,
                'expires': c.expires?.millisecondsSinceEpoch,
              },
            )
            .toList(),
  };

  void loadMap(Map<String, dynamic> map) {
    clear();
    if (map['version'] == 2 && map['cookies'] is List) {
      for (final raw in map['cookies'] as List) {
        if (raw is! Map) continue;
        final domain = _domain(raw['domain'] as String?);
        if (domain == null ||
            !_trusted(domain) ||
            raw['name'] is! String ||
            raw['value'] is! String) {
          continue;
        }
        final c = Cookie(
          raw['name'],
          raw['value'],
          domain: domain,
          path: raw['path'] as String? ?? '/',
          secure: true,
          hostOnly: raw['hostOnly'] == true,
          expires:
              raw['expires'] is num
                  ? DateTime.fromMillisecondsSinceEpoch(
                    (raw['expires'] as num).toInt(),
                  )
                  : null,
        );
        _cookies[_key(c)] = c;
      }
    } else {
      map.forEach((name, value) {
        if (value is String) set(name, value);
      });
    }
  }

  void clear() => _cookies.clear();
}
