import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class PermissionDeniedScreen extends StatelessWidget {
  final String? screenName;

  const PermissionDeniedScreen({super.key, this.screenName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Access Denied",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: msmRed,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: msmRed.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_person_rounded,
                  size: 80,
                  color: msmRed,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                "Restricted Access",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: textDark,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                screenName != null
                    ? "You do not have permission to view the $screenName screen."
                    : "You do not have permission to access this module.",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: textGrey),
              ),
              const SizedBox(height: 8),
              const Text(
                "Please contact your administrator to request access.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: textGrey),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: 200,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: msmRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Go Back",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
