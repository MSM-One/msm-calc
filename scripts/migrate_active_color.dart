import 'dart:io';

void main() {
  final dir = Directory('lib');
  if (!dir.existsSync()) {
    print('Directory lib not found');
    return;
  }
  dir.listSync(recursive: true).forEach((entity) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final content = entity.readAsStringSync();
      if (content.contains('activeColor:')) {
        final newContent =
            content.replaceAll('activeColor:', 'activeThumbColor:');
        entity.writeAsStringSync(newContent);
        print('Updated: ${entity.path}');
      }
    }
  });
}
