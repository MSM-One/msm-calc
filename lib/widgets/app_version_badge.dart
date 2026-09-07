import 'package:flutter/material.dart';
import '../services/app_version_service.dart';

/// Clean, subtle text badge displaying the dynamic application version.
class AppVersionBadge extends StatelessWidget {
  final bool showBuildNumber;
  final bool showPrefix;
  final TextStyle? style;
  final bool isClickable;

  const AppVersionBadge({
    super.key,
    this.showBuildNumber = false,
    this.showPrefix = true,
    this.style,
    this.isClickable = true,
  });

  @override
  Widget build(BuildContext context) {
    final prefix = showPrefix ? 'MSM Calc ' : '';
    final versionStr = AppVersionService.version;
    final buildStr =
        showBuildNumber ? ' (${AppVersionService.buildNumber})' : '';
    final label = '$prefix$versionStr$buildStr';

    final defaultStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: Colors.grey.shade500,
      letterSpacing: 0.3,
    );

    final textWidget = Text(
      label,
      style: style ?? defaultStyle,
    );

    if (!isClickable) return textWidget;

    return Semantics(
      button: true,
      label: 'Application version $label. Tap for details and updates.',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => AppVersionService.showAboutAppDialog(context),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: textWidget,
          ),
        ),
      ),
    );
  }
}
