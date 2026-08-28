// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

/// Web implementation for downloading PDF using AnchorElement.
void downloadFile(Uint8List bytes, String fileName) {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement()
    ..href = url
    ..setAttribute("download", fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}

void setDocumentTitle(String title) {
  html.document.title = title;
  final iframes = html.document.querySelectorAll('iframe');
  for (var node in iframes) {
    try {
      final iframe = node as html.IFrameElement;
      iframe.title = title;
    } catch (_) {}
  }
}
