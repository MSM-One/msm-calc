import 'dart:io';

void main() {
  final dir = Directory('lib');
  if (!dir.existsSync()) return;

  dir.listSync(recursive: true).forEach((entity) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final content = entity.readAsStringSync();
      if (content.contains('.withOpacity(')) {
        final newContent =
            content.replaceAll('.withOpacity(', '.withValues(alpha: ');
        entity.writeAsStringSync(newContent);
        print('Updated: ${entity.path}');
      }
    }
  });
}
