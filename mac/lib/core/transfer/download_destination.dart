import 'dart:io';

/// A private partial file belongs to one in-memory block set, never to a name.
/// The final path is only published after all range checks have succeeded.
class DownloadDestination {
  static final _partials = Expando<DownloadDestination>();
  final File destination;
  final Directory directory;
  final File partial;
  final Set<int> blocks;
  DownloadDestination._(
    this.destination,
    this.directory,
    this.partial,
    this.blocks,
  );

  static Future<DownloadDestination> open(
    String path,
    Set<int>? completed,
  ) async {
    final destination = File(path);
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('目标已存在，请选择其他目录或先重命名文件', path);
    }
    final blocks = completed ?? <int>{};
    final existing = _partials[blocks];
    if (existing != null &&
        existing.destination.absolute.path == destination.absolute.path &&
        existing.partial.existsSync()) {
      return existing;
    }
    blocks.clear();
    await destination.parent.create(recursive: true);
    final directory = await destination.parent.createTemp('.pi-download-');
    final partial = File('${directory.path}/data.part');
    await partial.create(exclusive: true);
    final result = DownloadDestination._(
      destination,
      directory,
      partial,
      blocks,
    );
    _partials[blocks] = result;
    return result;
  }

  void complete() {
    // Exclusive reservation prevents two completed tasks from replacing one
    // another. Reserve and rename synchronously, without an async gap.
    destination.createSync(exclusive: true);
    try {
      partial.renameSync(destination.path);
    } catch (_) {
      destination.deleteSync();
      rethrow;
    }
    discard(blocks);
  }

  static void discard(Set<int> blocks) {
    final target = _partials[blocks];
    if (target == null) return;
    try {
      if (target.directory.existsSync()) {
        target.directory.deleteSync(recursive: true);
      }
    } on FileSystemException {
      // A changed directory permission must not break queue accounting.
      // Never fall back to deleting the user destination.
    }
    _partials[blocks] = null;
    blocks.clear();
  }
}
