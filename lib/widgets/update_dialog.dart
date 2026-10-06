import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_colors.dart';

class UpdateDialog extends StatefulWidget {
  final String currentVersion;
  final String latestVersion;
  final String apkUrl;
  final String releaseNotes;
  final bool isForceUpdate;

  const UpdateDialog({
    super.key,
    required this.currentVersion,
    required this.latestVersion,
    required this.apkUrl,
    required this.releaseNotes,
    required this.isForceUpdate,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  int _downloadProgress = 0;
  String _statusMessage = '';
  bool _hasError = false;
  StreamSubscription<OtaEvent>? _otaSubscription;

  @override
  void dispose() {
    _otaSubscription?.cancel();
    super.dispose();
  }

  /// Converts Google Drive view links to direct file download URLs if applicable.
  static String _getDirectApkUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.contains('drive.google.com') && trimmed.contains('/file/d/')) {
      try {
        final regExp = RegExp(r'/file/d/([^/]+)');
        final match = regExp.firstMatch(trimmed);
        if (match != null && match.groupCount >= 1) {
          final fileId = match.group(1);
          return 'https://drive.google.com/uc?export=download&confirm=no_antivirus&id=$fileId';
        }
      } catch (_) {}
    }
    return trimmed;
  }

  Future<void> _launchExternalBrowser() async {
    final String targetUrl = _getDirectApkUrl(widget.apkUrl);
    debugPrint('[UpdateDialog] Launching external browser URL: $targetUrl');
    if (targetUrl.isNotEmpty) {
      final Uri uri = Uri.parse(targetUrl);
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (e) {
        debugPrint('[UpdateDialog] url_launcher error: $e');
      }
    }
  }

  Future<void> _launchApkUrl() async {
    final String targetUrl = _getDirectApkUrl(widget.apkUrl);
    debugPrint('[UpdateDialog] Tapped Update Now for URL: $targetUrl');
    _startOtaUpdate();
  }



  Future<void> _startOtaUpdate() async {
    if (_isDownloading) return;

    final String rawUrl = _getDirectApkUrl(widget.apkUrl);
    final String versionSuffix = widget.latestVersion.replaceAll('.', '_');
    final String apkFileName = 'msm_one_update_$versionSuffix.apk';

    setState(() {
      _isDownloading = true;
      _hasError = false;
      _downloadProgress = 0;
      _statusMessage = 'Preparing download... 0%';
    });

    // Use the raw URL directly — Supabase public storage URLs don't need redirect resolution.
    // Calling _resolveRedirectUrl first was causing HTTP 400 errors.
    debugPrint('[UpdateDialog] Starting OTA download from: $rawUrl');

    try {
      _otaSubscription = OtaUpdate()
          .execute(
        rawUrl,
        destinationFilename: apkFileName,
      )
          .listen(
        (OtaEvent event) {
          if (!mounted) return;

          switch (event.status) {
            case OtaStatus.DOWNLOADING:
              final int progress = int.tryParse(event.value ?? '0') ?? 0;
              setState(() {
                _downloadProgress = progress.clamp(0, 100);
                _statusMessage = 'Downloading update... $_downloadProgress%';
              });
              break;

            case OtaStatus.INSTALLING:
              setState(() {
                _downloadProgress = 100;
                _statusMessage = 'Launching package installer...';
              });
              break;

            case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
              _handleError(
                  'Permission denied. Please allow "Install unknown apps" in Settings.');
              break;

            case OtaStatus.DOWNLOAD_ERROR:
              debugPrint('[UpdateDialog] OTA DOWNLOAD_ERROR, falling back to HttpClient');
              _downloadViaDartHttpClient(rawUrl, apkFileName);
              break;

            case OtaStatus.CHECKSUM_ERROR:
              _handleError(
                  'Checksum verification failed. Package file may be corrupted.');
              break;

            case OtaStatus.INTERNAL_ERROR:
              debugPrint('[UpdateDialog] OTA INTERNAL_ERROR, falling back to HttpClient');
              _downloadViaDartHttpClient(rawUrl, apkFileName);
              break;

            case OtaStatus.ALREADY_RUNNING_ERROR:
              _handleError('Update process is already running.');
              break;

            default:
              _handleError('Update error (${event.status}). Please try again.');
              break;
          }
        },
        onError: (error) {
          debugPrint('[UpdateDialog] OTA stream error: $error');
          _downloadViaDartHttpClient(rawUrl, apkFileName);
        },
      );
    } catch (e) {
      debugPrint('[UpdateDialog] OTA exception: $e');
      _downloadViaDartHttpClient(rawUrl, apkFileName);
    }
  }

  Future<void> _downloadViaDartHttpClient(String url, String fileName) async {
    try {
      debugPrint('[UpdateDialog] HttpClient stream download: $url');

      setState(() {
        _statusMessage = 'Downloading update... 0%';
      });

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent',
          'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36');
      request.headers.set('Accept', 'application/vnd.android.package-archive, application/octet-stream, */*');
      request.followRedirects = true;
      request.maxRedirects = 5;

      final response = await request.close();
      final statusCode = response.statusCode;
      debugPrint('[UpdateDialog] HttpClient response status: $statusCode');

      // Accept any 2xx success response
      if (statusCode < 200 || statusCode >= 300) {
        debugPrint('[UpdateDialog] Download failed with HTTP $statusCode');
        _handleError('Download failed (HTTP $statusCode). Tap "Browser Download" below.');
        return;
      }

      final totalBytes = response.contentLength;
      int downloadedBytes = 0;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      final sink = file.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (mounted) {
          final progress = totalBytes > 0
              ? ((downloadedBytes / totalBytes) * 100).toInt()
              : -1; // indeterminate if content-length unknown
          setState(() {
            _downloadProgress = progress > 0 ? progress.clamp(0, 100) : _downloadProgress;
            _statusMessage = progress > 0
                ? 'Downloading update... ${progress.clamp(0, 100)}%'
                : 'Downloading update... ${(downloadedBytes / 1024 / 1024).toStringAsFixed(1)} MB';
          });
        }
      }

      await sink.flush();
      await sink.close();

      final fileSizeBytes = await file.length();
      debugPrint('[UpdateDialog] Download complete: ${(fileSizeBytes / 1024 / 1024).toStringAsFixed(2)} MB saved to ${file.path}');

      if (fileSizeBytes < 100000) {
        // File is suspiciously small (< 100KB), likely an error page
        debugPrint('[UpdateDialog] Downloaded file too small ($fileSizeBytes bytes), likely not a valid APK');
        _handleError('Download file appears invalid. Tap "Browser Download" below.');
        try { await file.delete(); } catch (_) {}
        return;
      }

      if (!mounted) return;
      setState(() {
        _downloadProgress = 100;
        _statusMessage = 'Installing update...';
      });

      // Use OTA plugin to trigger the Android package installer for the downloaded file
      _otaSubscription = OtaUpdate()
          .execute(
        file.path,
        destinationFilename: fileName,
      )
          .listen(
        (OtaEvent event) {
          if (!mounted) return;
          if (event.status == OtaStatus.INSTALLING) {
            setState(() {
              _statusMessage = 'Launching package installer...';
            });
          } else if (event.status == OtaStatus.INTERNAL_ERROR ||
              event.status == OtaStatus.DOWNLOAD_ERROR) {
            debugPrint('[UpdateDialog] Install via OTA failed, trying install_apk or browser');
            _installApkDirectly(file.path);
          }
        },
        onError: (_) {
          _installApkDirectly(file.path);
        },
      );
    } catch (e) {
      debugPrint('[UpdateDialog] Dart HttpClient error: $e');
      _handleError('Download error. Tap "Browser Download" below.');
    }
  }

  /// Attempts to install APK via Android intent, falls back to browser
  Future<void> _installApkDirectly(String filePath) async {
    try {
      // Try opening the file with Android's package installer via url_launcher
      final uri = Uri.parse('file://$filePath');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return;
      }
    } catch (e) {
      debugPrint('[UpdateDialog] Direct install failed: $e');
    }
    // Final fallback: open in browser
    _launchExternalBrowser();
  }

  void _handleError(String message) {
    if (!mounted) return;
    setState(() {
      _isDownloading = false;
      _hasError = true;
      _statusMessage = message;
    });

    debugPrint('[UpdateDialog] $message');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dialogContent = Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: msmRed.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.system_update_rounded,
                color: msmRed,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'App Update Available',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Version ${widget.latestVersion} is available (Current: v${widget.currentVersion})',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "What's New:",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.releaseNotes,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade800,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── In-App Native Download Progress / Status Indicator ──────────
            if (_isDownloading) ...[
              Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _downloadProgress / 100.0,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation<Color>(msmRed),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _statusMessage,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: msmRed,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ] else if (_hasError) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  _statusMessage,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            // ── Action Buttons ──────────────────────────────────────────────
            if (!_isDownloading) ...[
              Row(
                children: [
                  if (!widget.isForceUpdate) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          try {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString(
                                'dismissed_update_version', widget.latestVersion);
                          } catch (_) {}
                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey.shade400),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Later',
                          style: TextStyle(color: textDark),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _launchApkUrl,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: msmRed,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      child: Text(
                        _hasError ? 'Retry Update' : 'Update Now',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              if (_hasError) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _launchExternalBrowser,
                  icon: const Icon(Icons.open_in_browser_rounded, size: 16, color: Colors.grey),
                  label: const Text(
                    'Download via Browser instead',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );

    if (widget.isForceUpdate) {
      return PopScope(
        canPop: false,
        child: dialogContent,
      );
    }
    return dialogContent;
  }
}
