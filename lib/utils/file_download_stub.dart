import 'dart:typed_data';

/// Base function for downloading PDF.
/// Specific implementations will override this based on platform.
void downloadFile(Uint8List bytes, String fileName) {
  // Mobile/Desktop implementation usually handled by path_provider + share_plus
  // but we can provide a hook here if needed.
}

void setDocumentTitle(String title) {
  // Stub for web-only feature
}
