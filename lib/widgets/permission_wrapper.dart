import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';

class PermissionWrapper extends StatelessWidget {
  final String action;
  final Widget child;

  const PermissionWrapper({
    super.key,
    required this.action,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        if (userProvider.hasPermission(action)) {
          return child;
        }
        return const SizedBox.shrink(); // Hidden if no permission
      },
    );
  }
}
