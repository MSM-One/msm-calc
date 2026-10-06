import 'package:flutter/material.dart';
import '../models/app_user.dart';

class UserProvider extends ChangeNotifier {
  AppUser? _user;

  /// True while the app is still determining auth state (e.g., during splash
  /// silent-sign-in or session restoration). Set to false once setUser() or
  /// markInitialized() is called with a definitive result.
  bool _isInitializing = true;

  AppUser? get user => _user;

  /// Whether auth state is still being determined. Guards should show a
  /// loading placeholder instead of making routing decisions while true.
  bool get isInitializing => _isInitializing;

  void setUser(AppUser user) {
    _user = user;
    _isInitializing = false;
    notifyListeners();
  }

  void clearUser() {
    _user = null;
    _isInitializing = false;
    notifyListeners();
  }

  /// Call this when initialization is complete and user is confirmed to be
  /// unauthenticated (e.g., no saved session, no silent sign-in). This marks
  /// the initializing phase as done without setting a user.
  void markInitialized() {
    if (_isInitializing) {
      _isInitializing = false;
      notifyListeners();
    }
  }

  bool get isAuthenticated => _user != null;
  bool get isApproved => _user?.isApproved ?? false;
  bool get isPending => _user?.isPending ?? false;
  bool get isAdmin => _user?.isAdmin ?? false;

  bool hasPermission(String action) {
    return _user?.hasPermission(action) ?? false;
  }
}
