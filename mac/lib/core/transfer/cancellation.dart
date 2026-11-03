import 'dart:async';
import 'package:http/http.dart' as http;

/// One token per running transfer, never reused when a task resumes.
class TransferCancellation {
  final Completer<void> _aborted = Completer<void>();
  bool get isCanceled => _aborted.isCompleted;
  Future<void> get whenCanceled => _aborted.future;
  void cancel() {
    if (!isCanceled) _aborted.complete();
  }

  void check() {
    if (isCanceled) throw StateError('传输已取消');
  }
}

/// Preserves streamed/multipart bodies and lets IOClient abort in-flight I/O.
class TransferClient extends http.BaseClient {
  final http.Client inner;
  final TransferCancellation? cancellation;
  TransferClient(this.inner, [this.cancellation]);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    cancellation?.check();
    if (request.url.scheme != 'https') {
      throw StateError('只允许 HTTPS 请求');
    }
    // Credentials must never follow redirects implicitly to another origin.
    if (request.headers.containsKey('cookie') ||
        request.headers.containsKey('authorization')) {
      request.followRedirects = false;
    }
    final response = await inner.send(_AbortableProxy(request, cancellation));
    cancellation?.check();
    return response;
  }

  // The owner of the shared underlying client controls its lifetime.
  @override
  void close() {}
}

class _AbortableProxy extends http.BaseRequest with http.Abortable {
  final http.BaseRequest source;
  @override
  final Future<void>? abortTrigger;
  _AbortableProxy(this.source, TransferCancellation? cancellation)
    : abortTrigger =
          cancellation?.whenCanceled ??
          (source is http.Abortable ? source.abortTrigger : null),
      super(source.method, source.url) {
    headers.addAll(source.headers);
    followRedirects = source.followRedirects;
    maxRedirects = source.maxRedirects;
    persistentConnection = source.persistentConnection;
  }
  @override
  http.ByteStream finalize() {
    final body = source.finalize();
    headers.addAll(source.headers);
    contentLength = source.contentLength;
    super.finalize();
    return body;
  }
}
