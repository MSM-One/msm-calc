import 'dart:async'; // ✅ REQUIRED FOR POLLING
import 'dart:convert'; // ✅ REQUIRED FOR JSON
import 'dart:ui'; // ✅ REQUIRED FOR CUSTOM PAINTER
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/stock_transaction_screen.dart';
import 'screens/stock_month_report_screen.dart';
import 'screens/main_inventory_shell.dart';
import 'screens/inventory_history_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
export 'screens/login_screen.dart';
import 'widgets/authentication_guard.dart';
import 'services/app_config_service.dart';

import 'package:flutter/services.dart'; // ✅ REQUIRED FOR CLIPBOARD
import 'package:flutter_native_splash/flutter_native_splash.dart'; // ✅ REQUIRED FOR SPLASH
import 'package:url_launcher/url_launcher.dart';
import 'package:google_sign_in/google_sign_in.dart'; // ✅ REQUIRED FOR LOGOUT
import 'package:shared_preferences/shared_preferences.dart'; // ✅ REQUIRED FOR SAVING DATA
import 'package:share_plus/share_plus.dart'; // ✅ REQUIRED FOR SHARING
import 'models/stock_role.dart';
import 'models/user_session_notifier.dart';
import 'models/stock_models.dart';
import 'models/permission_model.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart'; // ✅ REQUIRED FOR debugPrint
import 'constants/app_colors.dart';
import 'utils/steel_helper.dart';
import 'utils/formatters.dart';
import 'utils/sorting_utils.dart';
import 'widgets/erp_segmented_filter.dart';
import 'widgets/global_view_wrapper.dart';
import 'widgets/screen_gate.dart';
import 'widgets/guarded_metric.dart';
import 'services/data_repository.dart';
import 'services/access_guard.dart';
import 'screens/sauda_report_screen.dart';
import 'screens/calculator_screen.dart';
import 'screens/sauda_booking_screen.dart';
import 'screens/sauda_entry_screen.dart';
import 'screens/manage_users_screen.dart';
import 'screens/professional_reports_screen.dart';
import 'package:window_manager/window_manager.dart'; // ✅ DESKTOP VIEWPORT CONTROL
// ✅ UNIFIED ADAPTIVE LAYOUT
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'providers/inventory_provider.dart';
import 'providers/user_provider.dart';
import 'services/sheet_service.dart';
import 'services/supabase_realtime_service.dart';

/// Global navigator key — allows nav operations from outside widget tree.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

// Shared utilities (SteelHelper, etc.) moved to lib/utils/steel_helper.dart

// Shared stock refresh signal for Dashboard/Transactions/Current Stock.

// ✅ GLOBAL SEARCH MODELS & UTILITIES
// Global search models moved to lib/widgets/global_view_wrapper.dart

// ✅ GLOBAL KEYBOARD & BACK HANDLER
class GlobalViewWrapperProxy extends StatelessWidget {
  final Widget child;
  const GlobalViewWrapperProxy({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          final isKeyboardVisible =
              MediaQuery.of(context).viewInsets.bottom > 0;
          if (isKeyboardVisible) {
            FocusScope.of(context).unfocus();
          } else {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop(result);
            }
          }
        },
        child: child,
      ),
    );
  }
}

// ✅ GLOBAL HELPERS FOR SHARING & LOGGING
Future<void> _safeShare(BuildContext context, String text,
    {String? subject}) async {
  try {
    print(
        "Sharing content: ${text.substring(0, text.length > 50 ? 50 : text.length)}...");
    await Share.share(text, subject: subject);
  } catch (e) {
    print("Share Error: $e");
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Error sharing: $e"), backgroundColor: Colors.red),
      );
    }
  }
}

void main() async {
  debugPrint('DEBUG: [main] started');
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('DEBUG: [main] WidgetsBinding initialized');

  await Supabase.initialize(
    url: 'https://wztyczjrakjsoifwtdda.supabase.co',
    anonKey: 'sb_publishable_wg9tZMFH_PwptXm9nuB1tg_WzW23AkY',
  );

  // ✅ WINDOW MANAGER SETUP (DESKTOP ONLY)
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux)) {
    try {
      await windowManager.ensureInitialized();
      WindowOptions windowOptions = const WindowOptions(
        size: Size(1280, 800),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
        title: "Metaroll Steel Mart",
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      debugPrint('DEBUG: [main] WindowManager error: $e');
    }
  }

  try {
    debugPrint('DEBUG: [main] Initializing Hive...');
    await Hive.initFlutter();
    debugPrint('DEBUG: [main] Initializing DataRepository...');
    await DataRepository.init();
    debugPrint('DEBUG: [main] DataRepository initialized');
    debugPrint('DEBUG: [main] Initializing SupabaseRealtimeService...');
    SupabaseRealtimeService.instance.initialize();
  } catch (e) {
    debugPrint('DEBUG: [main] Initialization error: $e');
  }

  debugPrint('DEBUG: [main] Calling runApp...');
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => InventoryProvider()..initTimer()),
      ],
      child: const MSMApp(),
    ),
  );
}

class MSMApp extends StatefulWidget {
  const MSMApp({super.key});

  @override
  State<MSMApp> createState() => _MSMAppState();
}

class _MSMAppState extends State<MSMApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 600), () {
        final ctx = appNavigatorKey.currentContext;
        if (ctx != null) {
          AppConfigService.checkForUpdates(ctx);
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      SupabaseRealtimeService.instance.pause();
    } else if (state == AppLifecycleState.resumed) {
      SupabaseRealtimeService.instance.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('DEBUG: [MSMApp] building MaterialApp');
    return MaterialApp(
      title: "Metaroll Steel Mart",
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      // ── Global Text Scaling Guard ────────────────────────────────────────
      // Clamps Android display/font size overrides to prevent RenderFlex
      // overflow on Large/XL settings while preserving accessibility scaling.
      builder: (context, child) {
        debugPrint('DEBUG: [MSMApp] builder called with child: $child');
        return Material(
          color: Colors.white,
          child: AuthenticationGuard(child: child!),
        );
      },
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: msmRed,
        scaffoldBackgroundColor: bgLight,
        colorScheme: ColorScheme.fromSeed(
          seedColor: msmRed,
          primary: msmRed,
          surface: Colors.white,
          onSurface: textDark,
        ).copyWith(
          surfaceTint: Colors.transparent,
        ),
        fontFamily:
            'Inter', // Switching to a more professional font if available, else Roboto
        appBarTheme: const AppBarTheme(
          backgroundColor: msmRed,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          iconTheme: IconThemeData(color: Colors.white),
          actionsIconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0, // Flat premium look
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: borderLight, width: 1),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: msmRed,
          unselectedItemColor: textGrey,
          selectedLabelStyle:
              TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: TextStyle(fontSize: 12),
          elevation: 8,
          type: BottomNavigationBarType.fixed,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        popupMenuTheme: const PopupMenuThemeData(
          surfaceTintColor: Colors.transparent,
          color: Colors.white,
        ),
        dividerTheme: const DividerThemeData(
          color: borderLight,
          thickness: 1.0,
          space: 1.0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF6F8FA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: msmRed, width: 1.5),
          ),
        ),
        chipTheme: const ChipThemeData(
          backgroundColor: Color(0xFFF5F5F5),
          selectedColor: msmRed,
          secondarySelectedColor: msmRed,
          labelStyle: TextStyle(
              fontSize: 12.0,
              fontWeight: FontWeight.w500,
              color: Color(0xFF212121)),
          secondaryLabelStyle: TextStyle(
              fontSize: 12.0, fontWeight: FontWeight.w500, color: Colors.white),
          shape: StadiumBorder(side: BorderSide(color: Colors.transparent)),
        ),
      ),
      routes: {
        '/sauda_entry': (context) => ScreenGate(
              canAccess: (s) => AccessGuard.can(Permissions.saudaView),
              screenName: 'Sauda Entry',
              child: const SaudaEntryScreen(),
            ),
        '/sauda_report': (context) => ScreenGate(
              canAccess: (s) => AccessGuard.can(Permissions.vendorPurchase),
              screenName: 'Sauda Report',
              child: const VendorPurchaseReportScreen(),
            ),
      },
      themeMode: ThemeMode.light,
      darkTheme: ThemeData(
        useMaterial3: true,
        primaryColor: msmRed,
        scaffoldBackgroundColor: bgLight,
        colorScheme: ColorScheme.fromSeed(
          seedColor: msmRed,
          primary: msmRed,
          surface: Colors.white,
          onSurface: textDark,
        ).copyWith(
          surfaceTint: Colors.transparent,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

/* ===================== SCREEN 0.5: SIMULATED PHONE AUTH ===================== */
// LoginScreen is imported from lib/screens/login_screen.dart

/* ===================== SCREEN 1: DASHBOARD ===================== */

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  final GoogleSignIn _googleSignIn = AuthService.googleSignIn;
  GoogleSignInAccount? _currentUser;
  String _displayName = "";
  String _email = "";
  String _phoneNumber = "";
  bool _isLoading = true;
  bool _isSyncing = false;

  Timer? _permissionPollTimer;

  String _selectedTab = 'Overview';
  final GlobalKey<ManageUsersScreenState> _manageUsersKey = GlobalKey();

  String _effectiveDisplayName() {
    if (_displayName.isNotEmpty) return _displayName;
    if (_currentUser?.displayName != null &&
        _currentUser!.displayName!.isNotEmpty) {
      return _currentUser!.displayName!;
    }
    if (_email.isNotEmpty) {
      final prefix = _email.split('@')[0];
      if (prefix.isNotEmpty) {
        return prefix[0].toUpperCase() + prefix.substring(1);
      }
    }
    return "User";
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAccess();
    // Aggressive polling every 30 seconds
    _permissionPollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshCurrentUserData(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _permissionPollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshCurrentUserData();
    }
  }

  /// Directly fetches the users list, finds the current user, updates UserSession,
  /// and triggers a UI rebuild. Performs nav guard if a screen was revoked.
  Future<void> _refreshCurrentUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('user_email');
      if (email == null || email.isEmpty) return;

      final previousSnapshot = UserSessionNotifier.instance.value;

      // Use centralized sync logic from DataRepository
      // This fetches from backend, normalizes, and updates UserSession
      await DataRepository.syncCurrentUser(email);

      if (!mounted) return;

      // Refresh the notifier which triggers UI rebuilds
      final changed = UserSessionNotifier.refreshFromSession();
      if (!changed) return;

      final newSnapshot = UserSessionNotifier.instance.value;

      // Check for generic permission revocation
      // If any major module permission is lost, we pop back to safety
      bool accessLost = false;

      // List of core module permissions to track for redirection
      final trackedPermissions = [
        Permissions.screensSaudaBooking,
        Permissions.screensQuotation,
        Permissions.screensCalculator,
        Permissions.screensStockInventory,
        Permissions.screensReports,
        Permissions.screensUsers,
        Permissions.screensSampleRate,
        Permissions.screensVendorPurchase,
      ];

      for (final perm in trackedPermissions) {
        if (previousSnapshot.canAccess(perm) && !newSnapshot.canAccess(perm)) {
          accessLost = true;
          break;
        }
      }

      if (accessLost) {
        // Return to Dashboard/Main Scaffolding
        appNavigatorKey.currentState?.popUntil((route) => route.isFirst);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '🔒 Your access permissions have been updated by an Administrator.',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'DISMISS',
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
        }
      }

      // Force rebuild local state to refresh Quick Actions
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[AUTH SYNC] Sync Error: $e');
    }
  }

  /// Legacy alias kept for any future internal use
  Future<void> _silentSync() => _refreshCurrentUserData();

  Future<void> _checkAccess() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('user_email') ?? "";
    if (email.isEmpty) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginScreen()));
      }
    } else {
      setState(() {
        _email = email;
        _displayName = prefs.getString('user_display_name') ?? "";
        _phoneNumber = prefs.getString('user_phone_number') ?? "";
        _isLoading = false;
      });
      _refreshCurrentUserData();
      if (mounted) {
        DataRepository.syncSheetData(context);
        DataRepository.syncERPStock(context);
      }
      _loadCurrentUser();
    }
  }

  Future<void> _saveProfileData(String name, String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_display_name', name);
    await prefs.setString('user_phone_number', phone);
    setState(() {
      _displayName = name;
      _phoneNumber = phone;
    });
  }

  void _loadCurrentUser() {
    _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount? account) {
      if (mounted) setState(() => _currentUser = account);
    });
    _googleSignIn.signInSilently();
  }

  Future<void> _handleSync() async {
    setState(() => _isSyncing = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Syncing latest data..."),
        duration: Duration(seconds: 1)));

    try {
      await DataRepository.syncSheetData(context, force: true);
      await DataRepository.syncERPStock(context, force: true);

      if (_selectedTab == 'Users' && _manageUsersKey.currentState != null) {
        await _manageUsersKey.currentState!.loadUsers();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("✅ Data Updated Successfully!"),
            backgroundColor: Colors.green));
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _loadUsersData() async {
    print("Fetching Users for Dashboard Admin Panel...");

    // Wait for the next frame so the AnimatedSwitcher can insert the widget
    // and the GlobalKey becomes attached to the current state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_manageUsersKey.currentState != null) {
        _manageUsersKey.currentState!.loadUsers();
      }
    });
  }

  bool _canAccess(String requiredScreen) {
    if (UserSession.currentRole == StockRole.ADMIN) return true;
    final access = UserSession.allowedAccess;
    if (access == 'All Screens') return true;

    // Fallback: If they have Yard/Factory access, they must see the Stock Inventory card
    if (requiredScreen == 'Stock Inventory Only' &&
        (access == 'Yard Location Only' || access == 'Factory Location Only')) {
      return true;
    }

    return access.contains(requiredScreen);
  }

  List<Widget> _getQuickActions([PermissionSnapshot? snap]) {
    final s = snap ?? UserSessionNotifier.instance.value;

    Future<void> syncAndNavigate(
        String screenName, String permission, Widget Function() builder) async {
      // Requirement 3: Refetch before showing permission-protected action
      if (kIsWeb) {
        await _refreshCurrentUserData();
      }

      if (!AccessGuard.can(permission)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("🔒 Access Denied: Permissions have been updated."),
            backgroundColor: Colors.red,
          ));
        }
        return;
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ScreenGate(
              canAccess: (s) => AccessGuard.can(permission),
              screenName: screenName,
              child: builder(),
            ),
          ),
        );
      }
    }

    // --- Data-driven Quick Actions Master List ---
    // Each action defines its own visibility rule against the current snapshot.
    // To add a new action, simply add a new entry here. No other code needs changing.
    final masterList = <_QuickAction>[
      _QuickAction(
        title: 'Quotation',
        icon: Icons.description,
        color: msmRed,
        isVisible: s.canAccessQuotation,
        isEnabled: true,
        onTap: () => syncAndNavigate(
          'Quotation',
          Permissions.screensQuotation,
          () => const CalculatorScreen(isQuotationMode: true),
        ),
      ),
      _QuickAction(
        title: 'Netrate Calc',
        icon: Icons.calculate,
        color: Colors.orange[700]!,
        isVisible: s.canAccessCalculator,
        isEnabled: true,
        onTap: () => syncAndNavigate(
          'Calculator',
          Permissions.screensCalculator,
          () => const CalculatorScreen(isQuotationMode: false),
        ),
      ),
      _QuickAction(
        title: 'Sauda Book',
        icon: Icons.book,
        color: Colors.purple,
        isVisible: s.canAccessSaudaBooking,
        isEnabled: true,
        onTap: () => syncAndNavigate(
          'Sauda Book',
          Permissions.screensSaudaBooking,
          () => const SaudaBookingScreen(),
        ),
      ),
      _QuickAction(
        title: 'Vendor Purchase',
        icon: Icons.track_changes,
        color: Colors.indigo,
        isVisible: s.canAccessVendorPurchaseScreen,
        isEnabled: true,
        onTap: () => syncAndNavigate(
          'Vendor Purchase',
          Permissions.screensVendorPurchase,
          () => const VendorPurchaseReportScreen(),
        ),
      ),
      _QuickAction(
        title: 'Stock Inventory',
        icon: Icons.inventory_2,
        color: Colors.teal,
        isVisible: s.canAccessStockInventory,
        isEnabled: true,
        onTap: () => syncAndNavigate(
          'Stock Inventory',
          Permissions.screensStockInventory,
          () => const MainInventoryShell(),
        ),
      ),
      _QuickAction(
        title: 'Reports',
        icon: Icons.bar_chart,
        color: Colors.blueGrey,
        isVisible: s.canAccessReports,
        isEnabled: true,
        onTap: () => syncAndNavigate(
          'Reports',
          Permissions.screensReports,
          () => const ProfessionalReportsScreen(),
        ),
      ),
    ];

    // Filter to only visible and enabled actions
    return masterList
        .where((a) => a.isVisible && a.isEnabled)
        .map((a) => _DashboardCard(
              title: a.title,
              icon: a.icon,
              color: a.color,
              isEnabled: a.isEnabled,
              onTap: a.onTap,
            ))
        .toList();
  }

  void _showProfile() async {
    String initialName = _displayName;
    if (initialName.isEmpty) {
      initialName = _currentUser?.displayName ?? "";
      if (initialName.isEmpty && _email.isNotEmpty) {
        initialName = _email.split('@')[0];
        if (initialName.isNotEmpty) {
          initialName = initialName[0].toUpperCase() + initialName.substring(1);
        }
      }
      if (initialName.isEmpty) initialName = "User";
    }
    String initialPhone = _phoneNumber;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          bool isEditing = false;
          // Using a local state within the StatefulBuilder
          return _ProfileBottomSheetContent(
            initialName: initialName,
            initialPhone: initialPhone,
            email: _email,
            photoUrl: _currentUser?.photoUrl,
            onSave: (newName, newPhone) async {
              await _saveProfileData(newName, newPhone);
              if (mounted) Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("✅ Profile Updated"),
                  backgroundColor: Colors.green));
            },
            onLogout: () async {
              Navigator.pop(context);
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear(); // Clear all for safety
              try {
                await _googleSignIn.signOut();
                await _googleSignIn.disconnect();
              } catch (e) {
                debugPrint("Logout Error: $e");
              }
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                        builder: (context) => const LoginScreen()),
                    (Route<dynamic> route) => false);
              }
            },
          );
        });
      },
    );
  }

  void _showContact() {
    const String supportNumber = "7391000346";
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(25),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                "Need Help?",
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: textDark),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                "Connect with us directly via Call or WhatsApp.",
                style: TextStyle(color: textGrey, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 30),
            Material(
              color: whatsappGreen,
              borderRadius: BorderRadius.circular(15),
              elevation: 4,
              shadowColor: whatsappGreen.withValues(alpha: 0.4),
              child: InkWell(
                onTap: () async {
                  var url = Uri.parse(
                      "https://wa.me/91$supportNumber?text=Hello%20Metaroll,%20I%20need%20assistance.");
                  if (!await launchUrl(url,
                      mode: LaunchMode.externalApplication)) {
                    throw 'Could not launch WhatsApp';
                  }
                  if (context.mounted) Navigator.pop(context);
                },
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble, color: Colors.white, size: 28),
                      SizedBox(width: 12),
                      Text(
                        "Chat on WhatsApp",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      )
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 15),
            InkWell(
              onTap: () async {
                final url = Uri.parse("tel:+91$supportNumber");
                if (await canLaunchUrl(url)) {
                  await launchUrl(url);
                }
                if (context.mounted) Navigator.pop(context);
              },
              borderRadius: BorderRadius.circular(15),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.call, color: Colors.blue, size: 28),
                    SizedBox(height: 5),
                    Text(
                      "Call Now",
                      style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                    Text("+91 $supportNumber",
                        style: TextStyle(color: Colors.blue, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
          backgroundColor: msmBg, body: Center(child: _MLoader(size: 80)));
    }

    return GlobalViewWrapper(
      child: Scaffold(
        backgroundColor: msmBg,
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: _handleSync,
            color: msmRed,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Red Header Card with bottom rounded corners
                  Container(
                      width: double.infinity,
                      padding: EdgeInsets.fromLTRB(
                          24, MediaQuery.of(context).padding.top + 16, 24, 40),
                      decoration: const BoxDecoration(
                        color: msmRed,
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(30),
                          bottomRight: Radius.circular(30),
                        ),
                      ),
                      child: Column(children: [
                        // Top App Bar Area inside the header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const SizedBox(width: 28), // balance for right icon
                            const Text(
                              "MSM Dashboard",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ValueListenableBuilder<bool>(
                                  valueListenable: DataRepository.isSyncing,
                                  builder: (context, isSyncing, child) {
                                    return Tooltip(
                                      message: isSyncing
                                          ? "Syncing..."
                                          : "Online & Synced",
                                      child: Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          color: isSyncing
                                              ? Colors.amberAccent
                                              : Colors.greenAccent,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: msmRed, width: 2),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert,
                                        color: Colors.white, size: 28),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(15)),
                                    onSelected: (value) {
                                      if (value == 'profile') _showProfile();
                                      if (value == 'sync') _handleSync();
                                      if (value == 'contact') _showContact();
                                    },
                                    itemBuilder: (BuildContext context) {
                                      return [
                                        const PopupMenuItem(
                                            value: 'profile',
                                            child: Row(children: [
                                              Icon(Icons.person,
                                                  color: textDark),
                                              SizedBox(width: 12),
                                              Text("Profile")
                                            ])),
                                        const PopupMenuItem(
                                            value: 'sync',
                                            child: Row(children: [
                                              Icon(Icons.sync, color: textDark),
                                              SizedBox(width: 12),
                                              Text("Sync Data")
                                            ])),
                                        const PopupMenuDivider(),
                                        const PopupMenuItem(
                                            value: 'contact',
                                            child: Row(children: [
                                              Icon(Icons.headset_mic_outlined,
                                                  color: textDark),
                                              SizedBox(width: 12),
                                              Text("Contact Us")
                                            ]))
                                      ];
                                    }),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // White pill logo
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Image.asset('assets/dashboard_logo.jpg',
                                height: 32,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.business,
                                        size: 30, color: msmRed))),
                        const SizedBox(height: 24),

                        const Text("Welcome back,",
                            style:
                                TextStyle(color: Colors.white70, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(_effectiveDisplayName(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold))
                      ])),

                  ValueListenableBuilder<PermissionSnapshot>(
                    valueListenable: UserSessionNotifier.instance,
                    builder: (context, s, _) {
                      if (!s.canAccessUsers) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        child: ERPSegmentedFilter(
                          options: const ['Overview', 'Users'],
                          selectedOption: _selectedTab,
                          onOptionSelected: (val) {
                            setState(() => _selectedTab = val);
                            if (val == 'Users') {
                              _loadUsersData();
                            }
                          },
                          activeBgColor: msmRed,
                          inactiveBgColor: Colors.grey.shade300,
                          activeTextColor: Colors.white,
                          inactiveTextColor: textDark,
                        ),
                      );
                    },
                  ),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _selectedTab == 'Users'
                        ? ManageUsersScreen(
                            key: _manageUsersKey, isEmbedded: true)
                        : Padding(
                            key: const ValueKey('OverviewTab'),
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_isSyncing)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 16.0),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: const LinearProgressIndicator(
                                        backgroundColor: Colors.transparent,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                kMetarollRed),
                                        minHeight: 3,
                                      ),
                                    ),
                                  ),
                                const Text("Quick Actions",
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: textDark)),
                                const SizedBox(height: 16),
                                ValueListenableBuilder<PermissionSnapshot>(
                                    valueListenable:
                                        UserSessionNotifier.instance,
                                    builder: (context, snap, _) {
                                      final actions = _getQuickActions(snap);
                                      if (actions.isEmpty) {
                                        return const Center(
                                            child: Text(
                                                "No accessible modules found.",
                                                style: TextStyle(
                                                    color: Colors.grey)));
                                      }
                                      List<Widget> rows = [];
                                      for (int i = 0;
                                          i < actions.length;
                                          i += 2) {
                                        rows.add(
                                          Row(
                                            children: [
                                              Expanded(child: actions[i]),
                                              if (i + 1 < actions.length)
                                                const SizedBox(width: 12),
                                              if (i + 1 < actions.length)
                                                Expanded(child: actions[i + 1]),
                                              if (i + 1 >= actions.length)
                                                const SizedBox(width: 12),
                                              if (i + 1 >= actions.length)
                                                const Spacer(),
                                            ],
                                          ),
                                        );
                                        if (i + 2 < actions.length) {
                                          rows.add(const SizedBox(height: 12));
                                        }
                                      }
                                      return Column(children: rows);
                                    }),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ===================== NEW: PROFILE BOTTOM SHEET CONTENT ===================== */

class _ProfileBottomSheetContent extends StatefulWidget {
  final String initialName;
  final String initialPhone;
  final String email;
  final String? photoUrl;
  final Function(String name, String phone) onSave;
  final VoidCallback onLogout;

  const _ProfileBottomSheetContent({
    required this.initialName,
    required this.initialPhone,
    required this.email,
    this.photoUrl,
    required this.onSave,
    required this.onLogout,
  });

  @override
  State<_ProfileBottomSheetContent> createState() =>
      _ProfileBottomSheetContentState();
}

class _ProfileBottomSheetContentState
    extends State<_ProfileBottomSheetContent> {
  late TextEditingController nameCtrl;
  late TextEditingController phoneCtrl;

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.initialName);
    phoneCtrl = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const crimsonColor = Color(0xFFEF1C24);
    const darkCrimson = Color(0xFFB80910);
    const textDarkColor = Color(0xFF0F172A);
    const textMutedColor = Color(0xFF64748B);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24,
        right: 24,
        top: 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header Row with Title & Close Icon
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 36),
              const Text(
                "Profile Settings",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: textDarkColor,
                  letterSpacing: -0.5,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded,
                      size: 18, color: textMutedColor),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Stylized Avatar & Camera Badge
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [crimsonColor, darkCrimson],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: widget.photoUrl != null
                      ? CircleAvatar(
                          radius: 40,
                          backgroundImage: NetworkImage(widget.photoUrl!),
                        )
                      : CircleAvatar(
                          radius: 40,
                          backgroundColor: crimsonColor.withValues(alpha: 0.1),
                          child: Text(
                            widget.initialName.isNotEmpty
                                ? widget.initialName[0].toUpperCase()
                                : "U",
                            style: const TextStyle(
                              color: crimsonColor,
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                ),
              ),
              // Camera / Edit Badge
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [crimsonColor, darkCrimson],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x30000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.initialName.isNotEmpty ? widget.initialName : "User Profile",
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: textDarkColor,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.email,
            style: const TextStyle(
              fontSize: 13,
              color: textMutedColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),

          // Active Status Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  "Metaroll SteelMart User",
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Inputs Section
          TextField(
            controller: nameCtrl,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: textDarkColor,
            ),
            decoration: InputDecoration(
              labelText: "Display Name",
              labelStyle: const TextStyle(color: textMutedColor, fontSize: 13),
              hintText: "Enter your full name",
              prefixIcon: const Icon(Icons.person_outline_rounded,
                  color: Color(0xFF64748B), size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: crimsonColor, width: 2),
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: phoneCtrl,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: textDarkColor,
            ),
            decoration: InputDecoration(
              labelText: "Phone Number",
              labelStyle: const TextStyle(color: textMutedColor, fontSize: 13),
              hintText: "+91 98765 43210",
              prefixIcon: const Icon(Icons.phone_outlined,
                  color: Color(0xFF64748B), size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: crimsonColor, width: 2),
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 24),

          // Save Changes button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [crimsonColor, darkCrimson],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x3DEF1C24),
                    blurRadius: 12,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () =>
                    widget.onSave(nameCtrl.text.trim(), phoneCtrl.text.trim()),
                icon: const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 20),
                label: const Text(
                  "Save Changes",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15.5,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Modern Logout button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                backgroundColor: const Color(0xFFFEF2F2),
                side: const BorderSide(color: Color(0xFFFECACA), width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                foregroundColor: const Color(0xFFDC2626),
              ),
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text(
                "Sign Out",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFFDC2626),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// Data Structure for Dashboard Actions
class _QuickAction {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isVisible;
  final bool isEnabled;

  const _QuickAction({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.isVisible,
    required this.isEnabled,
  });
}

// Helper Widget: Square Dashboard Card
class _DashboardCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isEnabled;

  const _DashboardCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isEnabled ? 1.0 : 0.5,
      child: Material(
        color: Colors.white,
        elevation: isEnabled ? 3 : 1,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Center(
                          child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Icon(icon, color: color, size: 26)),
                        ),
                        const SizedBox(height: 12),
                        Text(title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: textDark))
                      ])),
              if (!isEnabled)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: Icon(Icons.lock, size: 14, color: Colors.blueGrey),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardWideCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  const _DashboardWideCard(
      {required this.title,
      required this.subtitle,
      required this.icon,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
            onTap: onTap,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: Colors.grey[600])),
            title: Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: textDark)),
            subtitle: Text(subtitle,
                style: const TextStyle(fontSize: 12, color: textGrey)),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey)));
  }
}

class DeliveryOrderScreen extends StatefulWidget {
  const DeliveryOrderScreen({super.key});

  @override
  State<DeliveryOrderScreen> createState() => _DeliveryOrderScreenState();
}

class _DeliveryOrderScreenState extends State<DeliveryOrderScreen> {
  // Global Settings
  DateTime orderDate = DateTime.now();
  String billType = "Bill"; // Default
  TextEditingController obCtrl = TextEditingController();
  TextEditingController freightCtrl = TextEditingController();
  TextEditingController lorryCtrl = TextEditingController();

  // Party Details
  TextEditingController dealerCtrl = TextEditingController();
  TextEditingController billingNameCtrl = TextEditingController();
  TextEditingController billingAddressCtrl = TextEditingController();
  TextEditingController dispatchAddressCtrl = TextEditingController();

  // Items
  List<DOItemBlock> items = [];

  // Dynamic Data
  List<String> _itemTypes = [];
  Map<String, List<Map<String, dynamic>>> _sizeSdMap = {};
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _loadSheetData();
    _loadFromPrefs(); // ✅ Load saved data
  }

  // ✅ AUTO-SAVE LOGIC
  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    // Create simple map of data
    Map<String, dynamic> data = {
      'date': orderDate.toIso8601String(),
      'billType': billType,
      'ob': obCtrl.text,
      'freight': freightCtrl.text,
      'lorry': lorryCtrl.text,
      'dealer': dealerCtrl.text,
      'billing': billingNameCtrl.text,
      'bAddress': billingAddressCtrl.text,
      'dAddress': dispatchAddressCtrl.text,
      'items': items
          .map((b) => {
                'type': b.itemType,
                'sauda': b.saudaRateCtrl.text,
                'balance': b.balanceQtyCtrl.text,
                'rows': b.rows
                    .map((r) => {
                          'size': r.size,
                          'qty': r.qtyCtrl.text,
                          'net': r.netRateCtrl.text,
                          'bd': r.breakdownCtrl.text
                        })
                    .toList()
              })
          .toList()
    };

    await prefs.setString('do_draft_data', jsonEncode(data));
    if (mounted) setState(() => _isSaved = true);
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    String? raw = prefs.getString('do_draft_data');
    if (raw == null) {
      _addItemBlock();
      return;
    }

    try {
      Map<String, dynamic> data = jsonDecode(raw);
      setState(() {
        orderDate = DateTime.tryParse(data['date']) ?? DateTime.now();
        billType = data['billType'] ?? "Bill";
        obCtrl.text = data['ob'] ?? "";
        freightCtrl.text = data['freight'] ?? "";
        lorryCtrl.text = data['lorry'] ?? "";
        dealerCtrl.text = data['dealer'] ?? "";
        billingNameCtrl.text = data['billing'] ?? "";
        billingAddressCtrl.text = data['bAddress'] ?? "";
        dispatchAddressCtrl.text = data['dAddress'] ?? "";

        List<dynamic> loadedItems = data['items'] ?? [];
        items = loadedItems.map((b) {
          DOItemBlock block = DOItemBlock(key: UniqueKey());
          block.itemType = b['type'];
          block.saudaRateCtrl.text = b['sauda'] ?? "";
          block.balanceQtyCtrl.text = b['balance'] ?? "";
          List<dynamic> rows = b['rows'] ?? [];
          block.rows = rows.map((r) {
            DOSizeRow row = DOSizeRow();
            row.size = r['size'] ?? "";
            row.qtyCtrl.text = r['qty'] ?? "";
            row.netRateCtrl.text = r['net'] ?? "";
            row.breakdownCtrl.text = r['bd'] ?? "";
            return row;
          }).toList();
          return block;
        }).toList();

        if (items.isEmpty) _addItemBlock();
        _isSaved = true;
      });
    } catch (e) {
      _addItemBlock();
    }
  }

  void _resetForm() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('do_draft_data');
    setState(() {
      items.clear();
      _addItemBlock();
      dealerCtrl.clear();
      billingNameCtrl.clear();
      billingAddressCtrl.clear();
      dispatchAddressCtrl.clear();
      obCtrl.clear();
      freightCtrl.clear();
      lorryCtrl.clear();
      _isSaved = false;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("Form Reset Successfully")));
  }

  void _generateCSV() {
    StringBuffer csv = StringBuffer();
    csv.writeln("Item,Size,Qty(MT),Net Rate,Breakdown");
    for (var b in items) {
      for (var r in b.rows) {
        if (r.size.isNotEmpty) {
          csv.writeln(
              "${b.itemType},${r.size},${r.qtyCtrl.text},${r.netRateCtrl.text},\"${r.breakdownCtrl.text}\"");
        }
      }
    }
    Clipboard.setData(ClipboardData(text: csv.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("CSV Data Copied to Clipboard!")));
  }

  void _copyToClipboard() {
    // Reuse logic from Share
    StringBuffer msg = StringBuffer();
    msg.writeln("*Delivery Order Summary*");
    msg.writeln("Dealer: ${dealerCtrl.text}");
    int i = 1;
    for (var b in items) {
      for (var r in b.rows) {
        double q = double.tryParse(r.qtyCtrl.text) ?? 0;
        if (q > 0) {
          msg.writeln("▪ ${b.itemType} ${r.size} - ${q.toStringAsFixed(3)} MT");
          i++;
        }
      }
    }
    Clipboard.setData(ClipboardData(text: msg.toString()));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("Summary Copied!")));
  }

  // ✅ DYNAMIC DATA FETCHING
  Future<void> _loadSheetData() async {
    final data = await DataRepository.getSheetDataAsync(null);
    if (!mounted) return;

    final List<dynamic> rawItems = data['items'] ?? [];
    if (rawItems.isEmpty) return;

    final Map<String, List<Map<String, dynamic>>> tempSizes = {};

    for (var item in rawItems) {
      String name = item['name'].toString().trim();
      List<dynamic> rawSizes = item['sizes'] ?? [];

      // For DO, we need the SD value specifically
      List<Map<String, dynamic>> parsedSizes = rawSizes
          .map((s) => {
                'label': formatSizeDisplay(name, s['label'].toString().trim()),
                'sd': double.tryParse(s['sd'].toString()) ?? 0.0
              })
          .toList();

      if (tempSizes.containsKey(name)) {
        tempSizes[name]!.addAll(parsedSizes);
      } else {
        tempSizes[name] = parsedSizes;
      }
    }

    setState(() {
      _itemTypes = tempSizes.keys.toList()
        ..sort((a, b) => SortingUtils.compareCategories(a, b));
      _sizeSdMap = tempSizes;
    });
  }

  void _addItemBlock() {
    setState(() {
      items.add(DOItemBlock(key: UniqueKey()));
      _isSaved = false;
    });
  }

  void _removeItemBlock(int index) {
    setState(() {
      items.removeAt(index);
      _saveToPrefs();
    });
  }

  // ✅ SAFE LOOP IMPLEMENTATION
  void _recalcRow(DOItemBlock block, DOSizeRow row,
      {bool fromNetRate = false}) {
    double freight = double.tryParse(freightCtrl.text) ?? 0;
    double ob = double.tryParse(obCtrl.text) ?? 0;
    double saudaRate = double.tryParse(block.saudaRateCtrl.text) ?? 0;
    double sd = _getSizeSD(block.itemType, row.size);

    bool isNC = (billType == "NC");
    bool applyDeduction =
        isNC && (block.itemType != "Binding Wire" && block.itemType != "Nails");
    double deduction = applyDeduction ? 3000 : 0;

    String dedStr = applyDeduction ? " - 3000" : "";
    String obStr = ob > 0 ? " + $ob(OB)" : "";

    if (fromNetRate) {
      // REVERSE
      double currentNet = double.tryParse(row.netRateCtrl.text) ?? 0;
      if (currentNet > 0) {
        double base = currentNet / 1.18;
        double calculatedSauda = base - sd - 255 - freight - ob + deduction;
        block.saudaRateCtrl.text = calculatedSauda.round().toString();
        row.breakdownCtrl.text =
            "${calculatedSauda.round()} + $sd$dedStr + 255 + $freight$obStr + 18%";
        for (var otherRow in block.rows) {
          if (otherRow != row) _recalcRow(block, otherRow);
        }
      }
    } else {
      // FORWARD
      double base = saudaRate + sd + 255 + freight + ob - deduction;
      double finalRate = base * 1.18;
      row.netRateCtrl.text = finalRate.round().toString();
      row.breakdownCtrl.text =
          "${saudaRate.toStringAsFixed(0)} + $sd$dedStr + 255 + $freight$obStr + 18%";
    }
    _saveToPrefs();
  }

  void _recalcAll() {
    for (var block in items) {
      for (var row in block.rows) {
        _recalcRow(block, row);
      }
    }
    _saveToPrefs();
  }

  // ✅ ROBUST LOOP - NO CRASH
  double _getSizeSD(String? item, String size) {
    if (item == null || size.isEmpty) return 0;

    // 1. Try Dynamic
    List<Map<String, dynamic>>? list = _sizeSdMap[item];
    if (list != null) {
      for (var element in list) {
        if (element['label'] == size) return (element['sd'] as num).toDouble();
      }
    }

    // 2. Try Fallback (HTML Data)
    var htmlData = DOConstants.SIZE_SD_LIST[item];
    if (htmlData != null) {
      for (var pair in htmlData) {
        if (pair[0].toString() == size) return (pair[1] as num).toDouble();
      }
    }

    return 0;
  }

  double _getTotalQty() {
    double total = 0;
    for (var b in items) {
      for (var r in b.rows) {
        total += double.tryParse(r.qtyCtrl.text) ?? 0;
      }
    }
    return total;
  }

  void _shareDO() async {
    StringBuffer msg = StringBuffer();
    msg.writeln("*Delivery Order*");
    msg.writeln("Date: ${orderDate.day}/${orderDate.month}/${orderDate.year}");
    msg.writeln("Dealer: ${dealerCtrl.text}");
    msg.writeln("Lorry: ${lorryCtrl.text}");
    msg.writeln("Bill Type: $billType");
    msg.writeln("");

    int i = 1;
    for (var b in items) {
      for (var r in b.rows) {
        double q = double.tryParse(r.qtyCtrl.text) ?? 0;
        if (q > 0) {
          msg.writeln("▪ ${b.itemType} ${r.size} - ${q.toStringAsFixed(3)} MT");
          i++;
        }
      }
    }
    msg.writeln("\n*Total Qty: ${_getTotalQty().toStringAsFixed(3)} MT*");

    _safeShare(context, msg.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text("Delivery Order"), elevation: 0),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ✅ ACTION BAR
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: _isSaved
                              ? Colors.green.shade50
                              : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _isSaved ? Colors.green : Colors.orange)),
                      child: Row(children: [
                        Icon(Icons.circle,
                            size: 10,
                            color: _isSaved ? Colors.green : Colors.orange),
                        const SizedBox(width: 6),
                        Text(_isSaved ? "Saved" : "Unsaved",
                            style: TextStyle(
                                color: _isSaved ? Colors.green : Colors.orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 12))
                      ]),
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                        avatar: const Icon(Icons.refresh, size: 16),
                        label: const Text("Reset"),
                        onPressed: _resetForm,
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Colors.grey)),
                    const SizedBox(width: 8),
                    ActionChip(
                        avatar: const Icon(Icons.download, size: 16),
                        label: const Text("CSV"),
                        onPressed: _generateCSV,
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Colors.blue)),
                    const SizedBox(width: 8),
                    ActionChip(
                        avatar: const Icon(Icons.copy, size: 16),
                        label: const Text("Copy"),
                        onPressed: _copyToClipboard,
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Colors.orange)),
                    const SizedBox(width: 8),
                    ActionChip(
                        avatar: const Icon(Icons.print, size: 16),
                        label: const Text("Print"),
                        onPressed: _shareDO,
                        backgroundColor: msmRed,
                        labelStyle: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- GLOBAL SETTINGS ---
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                          child: InkWell(
                        onTap: () async {
                          final now = DateTime.now();
                          final today = DateTime(
                              now.year, now.month, now.day, 23, 59, 59);
                          DateTime? p = await showDatePicker(
                            context: context,
                            initialDate:
                                orderDate.isAfter(today) ? now : orderDate,
                            firstDate: DateTime(2020),
                            lastDate: today,
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: const ColorScheme.light(
                                    primary: Color(0xFFD32F2F),
                                    onPrimary: Colors.white,
                                    onSurface: Color(0xFF1E293B),
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (p != null) setState(() => orderDate = p);
                          _saveToPrefs();
                        },
                        child: InputDecorator(
                            decoration: msmInputDeco("Date"),
                            child: Text(
                                "${orderDate.day}/${orderDate.month}/${orderDate.year}")),
                      )),
                      const SizedBox(width: 10),
                      Expanded(
                          child: DropdownButtonFormField<String>(
                              initialValue: billType,
                              decoration: msmInputDeco("Bill Type"),
                              items: ["Bill", "NC"]
                                  .map((t) => DropdownMenuItem(
                                      value: t, child: Text(t)))
                                  .toList(),
                              onChanged: (v) {
                                setState(() => billType = v!);
                                _recalcAll();
                              }))
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: TextField(
                              controller: obCtrl,
                              decoration: msmInputDeco("OB"),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => _recalcAll())),
                      const SizedBox(width: 10),
                      Expanded(
                          child: TextField(
                              controller: freightCtrl,
                              decoration: msmInputDeco("Freight"),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => _recalcAll())),
                      const SizedBox(width: 10),
                      Expanded(
                          child: TextField(
                              controller: lorryCtrl,
                              decoration: msmInputDeco("Lorry No."),
                              onChanged: (v) => _saveToPrefs())),
                    ])
                  ]),
                ),
              ),
              const SizedBox(height: 16),

              // --- PARTY DETAILS ---
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    TextField(
                        controller: dealerCtrl,
                        decoration: msmInputDeco("Dealer Name"),
                        onChanged: (v) => _saveToPrefs()),
                    const SizedBox(height: 10),
                    TextField(
                        controller: billingNameCtrl,
                        decoration: msmInputDeco("Billing Name"),
                        onChanged: (v) => _saveToPrefs()),
                    const SizedBox(height: 10),
                    TextField(
                        controller: billingAddressCtrl,
                        decoration: msmInputDeco("Billing Address"),
                        maxLines: 2,
                        onChanged: (v) => _saveToPrefs()),
                    const SizedBox(height: 10),
                    TextField(
                        controller: dispatchAddressCtrl,
                        decoration: msmInputDeco("Dispatch Address"),
                        maxLines: 2,
                        onChanged: (v) => _saveToPrefs()),
                  ]),
                ),
              ),
              const SizedBox(height: 20),

              // --- ITEM BLOCKS ---
              ...items.asMap().entries.map((entry) {
                int idx = entry.key;
                DOItemBlock block = entry.value;

                // Use dynamic item types if available, else fallback to constants
                List<String> typeList =
                    _itemTypes.isNotEmpty ? _itemTypes : DOConstants.ITEM_LIST;

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                            child: InkWell(
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(24))),
                              builder: (ctx) {
                                String query = "";
                                String sortBy = "Priority";
                                return StatefulBuilder(
                                    builder: (c, setSheetState) {
                                  var filtered = applyPrioritizedSearch(
                                      query, typeList, (t) => t);
                                  if (sortBy == "Priority") {
                                    filtered.sort((a, b) =>
                                        SortingUtils.compareCategories(a, b));
                                  } else if (sortBy == "Name A-Z") {
                                    if (query.isEmpty) {
                                      filtered.sort((a, b) => a.compareTo(b));
                                    }
                                  } else if (sortBy == "Name Z-A") {
                                    filtered.sort((a, b) => b.compareTo(a));
                                  }

                                  return Padding(
                                    padding: EdgeInsets.only(
                                        bottom:
                                            MediaQuery.of(c).viewInsets.bottom,
                                        top: 24,
                                        left: 16,
                                        right: 16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text("Select Item",
                                                style: TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: textDark)),
                                            IconButton(
                                              icon: const Icon(Icons.sort,
                                                  color: msmRed),
                                              onPressed: () {
                                                final opts = [
                                                  "Priority",
                                                  "Name A-Z",
                                                  "Name Z-A"
                                                ];
                                                showModalBottomSheet(
                                                    context: context,
                                                    builder: (c2) => Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(24),
                                                          child: Column(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: opts
                                                                  .map((o) =>
                                                                      ListTile(
                                                                        title: Text(
                                                                            o,
                                                                            style:
                                                                                TextStyle(fontWeight: sortBy == o ? FontWeight.bold : FontWeight.normal, color: sortBy == o ? msmRed : textDark)),
                                                                        onTap:
                                                                            () {
                                                                          setSheetState(() =>
                                                                              sortBy = o);
                                                                          Navigator.pop(
                                                                              c2);
                                                                        },
                                                                      ))
                                                                  .toList()),
                                                        ));
                                              },
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        TextField(
                                          autofocus: true,
                                          decoration: msmInputDeco(
                                              "Search Item...",
                                              prefix: const Icon(Icons.search,
                                                  color: textGrey)),
                                          onChanged: (v) =>
                                              setSheetState(() => query = v),
                                        ),
                                        const SizedBox(height: 16),
                                        ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight: MediaQuery.of(context)
                                                    .size
                                                    .height *
                                                0.7,
                                          ),
                                          child: Expanded(
                                            child: filtered.isEmpty
                                                ? const Center(
                                                    child:
                                                        Text("No item found"))
                                                : ListView.separated(
                                                    itemCount: filtered.length,
                                                    separatorBuilder: (c, i) =>
                                                        const Divider(),
                                                    itemBuilder: (context, i) =>
                                                        ListTile(
                                                      title: Text(filtered[i],
                                                          style: const TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color: textDark)),
                                                      onTap: () =>
                                                          Navigator.pop(context,
                                                              filtered[i]),
                                                    ),
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                      ],
                                    ),
                                  );
                                });
                              },
                            ).then((v) {
                              if (v != null) {
                                setState(() => block.itemType = v);
                                _recalcAll();
                              }
                            });
                          },
                          child: InputDecorator(
                            decoration: msmInputDeco("Select Item").copyWith(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 12),
                                isDense: true),
                            child: Text(block.itemType ?? "Select",
                                style: TextStyle(
                                    fontSize: 13,
                                    color: block.itemType == null
                                        ? textGrey
                                        : textDark)),
                          ),
                        )),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                                controller: block.saudaRateCtrl,
                                decoration: msmInputDeco("Sauda Rate").copyWith(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 12),
                                    isDense: true),
                                keyboardType: TextInputType.number,
                                onChanged: (v) => _recalcAll())),
                        IconButton(
                            icon: const Icon(Icons.delete, color: msmRed),
                            onPressed: () => _removeItemBlock(idx))
                      ]),
                      const SizedBox(height: 10),
                      TextField(
                          controller: block.balanceQtyCtrl,
                          decoration: msmInputDeco("Balance Qty (MT)"),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => _saveToPrefs()),

                      const Divider(),
                      // ✅ UPDATED ROW LAYOUT: Size | Qty | Net Rate (Green) | Breakdown
                      const Row(children: [
                        Expanded(
                            flex: 3,
                            child: Text("SIZE *",
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey))),
                        Expanded(
                            flex: 2,
                            child: Text("QTY (MT)",
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey))),
                        Expanded(
                            flex: 2,
                            child: Text("NET RATE",
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey))),
                        Expanded(
                            flex: 4,
                            child: Text("BREAKDOWN",
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey))),
                        SizedBox(width: 30)
                      ]),
                      const SizedBox(height: 4),

                      ...block.rows.asMap().entries.map((rEntry) {
                        int rIdx = rEntry.key;
                        DOSizeRow row = rEntry.value;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(children: [
                            Expanded(
                                flex: 3,
                                child: InkWell(
                                    onTap: () => _showSizeSearch(block, row),
                                    child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12, horizontal: 8),
                                        decoration: BoxDecoration(
                                            border: Border.all(
                                                color: Colors.grey.shade300),
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        child: Text(
                                            row.size.isEmpty
                                                ? "Select Size"
                                                : row.size,
                                            overflow: TextOverflow.ellipsis)))),
                            const SizedBox(width: 5),
                            Expanded(
                                flex: 2,
                                child: TextField(
                                    controller: row.qtyCtrl,
                                    decoration:
                                        msmTableInputDeco(hint: "0.000"),
                                    keyboardType: TextInputType.number,
                                    onChanged: (v) {
                                      setState(() {});
                                      _saveToPrefs();
                                    })),
                            const SizedBox(width: 5),
                            // ✅ GREEN NET RATE INPUT
                            Expanded(
                                flex: 2,
                                child: TextField(
                                    controller: row.netRateCtrl,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green),
                                    decoration: msmTableInputDeco(
                                        hint: "Auto",
                                        fillColor: Colors.green.shade50),
                                    onChanged: (v) => _recalcRow(block, row,
                                        fromNetRate: true))),
                            const SizedBox(width: 5),
                            Expanded(
                                flex: 4,
                                child: TextField(
                                    controller: row.breakdownCtrl,
                                    readOnly: true,
                                    style: const TextStyle(fontSize: 11),
                                    decoration: msmTableInputDeco(hint: "—"))),
                            IconButton(
                                icon: const Icon(Icons.remove_circle,
                                    color: Colors.red, size: 20),
                                onPressed: () => setState(() {
                                      block.rows.removeAt(rIdx);
                                      _saveToPrefs();
                                    }))
                          ]),
                        );
                      }),
                      TextButton.icon(
                          onPressed: () =>
                              setState(() => block.rows.add(DOSizeRow())),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text("Add Size"))
                    ]),
                  ),
                );
              }),

              SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                      onPressed: _addItemBlock,
                      icon: const Icon(Icons.add),
                      label: const Text("Add Item Block"))),
              // Added dynamic padding for fixed bottom bar
              SizedBox(
                  height:
                      MediaQuery.of(context).viewInsets.bottom > 0 ? 20 : 100),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(color: Colors.white, boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, -2))
        ]),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text("Total: ${_getTotalQty().toStringAsFixed(3)} MT",
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: msmRed,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
              onPressed: _shareDO,
              icon: const Icon(Icons.share),
              label: const Text("Share Order"))
        ]),
      ),
    );
  }

  void _showSizeSearch(DOItemBlock block, DOSizeRow row) {
    if (block.itemType == null) return;

    // 1. Try Dynamic
    List<Map<String, dynamic>> sizes = _sizeSdMap[block.itemType] ?? [];

    // 2. Try Fallback (HTML Data)
    if (sizes.isEmpty) {
      var htmlData = DOConstants.SIZE_SD_LIST[block.itemType];
      if (htmlData != null) {
        sizes = htmlData
            .map((e) =>
                {'label': e[0].toString(), 'sd': (e[1] as num).toDouble()})
            .toList();
      }
    }

    showModalBottomSheet(
        context: context,
        builder: (c) {
          String query = "";
          String sortBy = "Thickness High-Low";
          return StatefulBuilder(builder: (context, setSheetState) {
            var filtered = applyPrioritizedSearch(
                query, sizes, (item) => item['label'].toString());

            if (sortBy == "Thickness High-Low") {
              filtered.sort((a, b) => SortingUtils.compareSizes(
                  b['label'].toString(), a['label'].toString()));
            } else if (sortBy == "Thickness Low-High")
              filtered.sort((a, b) => SortingUtils.compareSizes(
                  a['label'].toString(), b['label'].toString()));
            else if (sortBy == "Alpha A-Z") {
              if (query.isEmpty) {
                filtered.sort((a, b) =>
                    a['label'].toString().compareTo(b['label'].toString()));
              }
            }

            return Container(
                padding: const EdgeInsets.all(16),
                height: 500,
                child: Column(children: [
                  Row(
                    children: [
                      Expanded(
                          child: TextField(
                              autofocus: true,
                              decoration: msmInputDeco("Search Size"),
                              onChanged: (v) =>
                                  setSheetState(() => query = v))),
                      IconButton(
                        icon: const Icon(Icons.sort, color: msmRed),
                        onPressed: () {
                          final opts = [
                            "Thickness High-Low",
                            "Thickness Low-High",
                            "Alpha A-Z"
                          ];
                          showModalBottomSheet(
                              context: context,
                              builder: (c) => Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: opts
                                            .map((o) => ListTile(
                                                  title: Text(o,
                                                      style: TextStyle(
                                                          fontWeight: sortBy ==
                                                                  o
                                                              ? FontWeight.bold
                                                              : FontWeight
                                                                  .normal,
                                                          color: sortBy == o
                                                              ? msmRed
                                                              : textDark)),
                                                  onTap: () {
                                                    setSheetState(
                                                        () => sortBy = o);
                                                    Navigator.pop(c);
                                                  },
                                                ))
                                            .toList()),
                                  ));
                        },
                      ),
                    ],
                  ),
                  Expanded(
                      child: ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (c, i) => ListTile(
                              title: Text(filtered[i]['label']),
                              onTap: () {
                                setState(() {
                                  row.size = filtered[i]['label'];
                                  _recalcAll();
                                });
                                Navigator.pop(c);
                              })))
                ]));
          });
        });
  }
}

class DOItemBlock {
  Key? key;
  String? itemType;
  TextEditingController saudaRateCtrl = TextEditingController();
  TextEditingController balanceQtyCtrl = TextEditingController();
  List<DOSizeRow> rows = [DOSizeRow()];
  DOItemBlock({this.key});
}

class DOSizeRow {
  String size = "";
  TextEditingController qtyCtrl = TextEditingController();
  TextEditingController netRateCtrl = TextEditingController();
  TextEditingController breakdownCtrl = TextEditingController();
}

class DOConstants {
  static const List<String> ITEM_LIST = [
    "MS Pipe",
    "MS Angle",
    "MS Channel",
    "Flats",
    "ERW Pipe",
    "Sqr Bar",
    "Round Bar",
    "HR Pipe",
    "GATE Channel",
    "MS Structure ISMC",
    "Binding Wire",
    "Nails"
  ];

  // ✅ FULL DATA FROM YOUR HTML (Included for offline fallback)
  static const Map<String, List<dynamic>> SIZE_SD_LIST = {
    "MS Pipe": [
      ["0.75\" 19x19(1.2) 4kg", 7000],
      ["0.75\" 19x19(1.6) 5kg", 6500],
      ["1\" 25x25(1.2) 6kg", 5000]
    ],
    "MS Angle": [
      ["25x3 (6.2 kg)", 7800],
      ["35x5 (14.5kg)", 7200]
    ],
    // ... (This list can be extended with all 200+ entries from your HTML if needed)
  };
}

// ... (Rest of Calculator & Quotation screens remain same as previous)

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  @override
  void initState() {
    super.initState();
    _refreshRole();
  }

  Future<void> _refreshRole() async {
    await DataRepository.syncCurrentUser();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("Current User Role: ${UserSession.currentRole}");

    // Corrected condition: handles Enum comparison via toString()
    bool isAdmin =
        (UserSession.currentRole.toString().toUpperCase().contains('ADMIN')) ||
            (UserSession.userEmail == 'j2833945@gmail.com');
    debugPrint("isAdmin: $isAdmin"); // Verification for console logs

    return Scaffold(
      backgroundColor: bgLight,
      appBar: AppBar(
        title: const Text("Reports",
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white)),
        backgroundColor: msmRed,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildReportItem(
              context, "Daily Transaction Log", Icons.today, Colors.blue),
          _buildReportItem(context, "Monthly Movement Report",
              Icons.calendar_month, Colors.purple),
          _buildReportItem(
              context, "Closing Stock Summary", Icons.summarize, Colors.teal),
          _buildReportItem(context, "Low Stock Alerts",
              Icons.warning_amber_rounded, Colors.orange),
          _buildReportItem(context, "Lorry & Transport Log",
              Icons.local_shipping, Colors.indigo),
          _buildReportItem(context, "Audit Trail (Reversals)",
              Icons.history_rounded, Colors.red),
          if (isAdmin) ...[
            ListTile(
              tileColor: Colors.red.withValues(alpha: 0.05),
              leading:
                  const Icon(Icons.admin_panel_settings, color: Colors.red),
              title: const Text("Manage Users & Permissions",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ScreenGate(
                    canAccess: (s) => AccessGuard.can(Permissions.screensUsers),
                    screenName: 'User Management',
                    child: const AdminUserManagementScreen(),
                  ),
                ),
              ),
            ),
            const Divider(),
            const Divider(height: 48),
            _buildReportItem(context, "Reset Dashboard to Zero",
                Icons.restart_alt_rounded, Colors.orange.shade800),
          ],
        ],
      ),
    );
  }

  Widget _buildReportItem(
      BuildContext context, String title, IconData icon, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: color, size: 28),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: const Icon(Icons.chevron_right, color: textGrey),
        onTap: () {
          if (title == "Monthly Movement Report") {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const StockMonthReportScreen()));
          } else if (title == "Manage Users") {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const AdminUserManagementScreen()));
          } else if (title == "Daily Transaction Log") {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const MainInventoryShell(
                        initialTab: 1))); // Transactions -> Today
          } else if (title == "Low Stock Alerts") {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const MainInventoryShell(
                        initialTab: 0, initialFilter: 'LOW')));
          } else if (title == "Audit Trail (Reversals)") {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const TransactionHistoryScreen(
                        initialType:
                            'REVERSED'))); // Hypothetical 'REVERSED' filter
          } else if (title == "Reset Dashboard to Zero") {
            _showResetConfirmation(context);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("$title reported coming soon!")));
          }
        },
      ),
    );
  }

  void _showResetConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reset Dashboard?"),
        content: const Text(
            "This will set current stock calculations to zero on your dashboard.\n\nYour Google Sheet data will remain 100% safe and untouched."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL")),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade800),
              onPressed: () async {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Resetting dashboard...")));
                final success = await SheetService.resetDashboard();
                if (success) {
                  // 🚀 CRITICAL FIX: Clear local cache & pending transactions immediately
                  await DataRepository.clearLocalCacheOnly();

                  // Refresh ERP stock to reflect the zeroed state
                  await DataRepository.getERPStockAsync(null,
                      forceRefresh: true);

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content:
                            Text("Dashboard Reset Successful! (Cache Cleared)"),
                        backgroundColor: Colors.teal));
                  }
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Reset Failed. Please try again."),
                        backgroundColor: msmRed));
                  }
                }
              },
              child:
                  const Text("RESET", style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }
}

// ===================== SCREEN X: STOCK DASHBOARD =====================

// ===================== SCREEN X: NESTED STOCK ENTRY MODAL =====================

// ===================== SCREEN X: CURRENT STOCK =====================

// End of State

// Helper Model for UI Grouping
class ItemGroup {
  final String itemName;
  final String category;
  final String? location;
  final List<ItemVariant> variants = [];

  ItemGroup(this.itemName, this.category, {this.location});

  double get totalMT => variants.fold(0.0, (sum, v) => sum + v.currentStockMT);
  bool get hasLowStock => variants.any((v) => v.currentStockMT <= v.minStock);
}

// Dead code removed.

// ===================== SCREEN X: MONTH-WISE REPORT =====================

/* ===================== NEW: ADMIN USER MANAGEMENT ===================== */

class AdminUserManagementScreen extends StatefulWidget {
  const AdminUserManagementScreen({super.key});

  @override
  State<AdminUserManagementScreen> createState() =>
      _AdminUserManagementScreenState();
}

class _AdminUserManagementScreenState extends State<AdminUserManagementScreen> {
  List<dynamic> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      setState(() => _isLoading = true);
      final users = await SheetService.fetchUsers();
      if (mounted) {
        setState(() {
          _users = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Load Users UI Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showPermissionsSheet(Map<String, dynamic> user) {
    bool isApproved = user['status'] == 'Approved';
    bool canDelete = user['canDelete'] == true;
    bool canReports = user['canReports'] == true;
    String location = user['location'] ?? 'ALL';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Permissions: ${user['email']}",
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const Divider(height: 32),
              SwitchListTile(
                title: const Text("Approve User"),
                subtitle: Text(isApproved ? "Approved" : "Pending"),
                value: isApproved,
                activeThumbColor: Colors.green,
                onChanged: (val) => setSheetState(() => isApproved = val),
              ),
              SwitchListTile(
                title: const Text("Allow Delete"),
                value: canDelete,
                onChanged: (val) => setSheetState(() => canDelete = val),
              ),
              SwitchListTile(
                title: const Text("Allow Reports"),
                value: canReports,
                onChanged: (val) => setSheetState(() => canReports = val),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text("Assigned Location",
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonFormField<String>(
                  initialValue: ['YARD', 'FACTORY', 'ALL'].contains(location)
                      ? location
                      : 'ALL',
                  items: ['YARD', 'FACTORY', 'ALL']
                      .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                      .toList(),
                  onChanged: (val) => setSheetState(() => location = val!),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    final updatedUser = {
                      'email': user['email'],
                      'status': isApproved ? 'Approved' : 'Pending',
                      'canDelete': canDelete,
                      'canReports': canReports,
                      'location': location,
                      'role': isApproved ? 'Operator' : 'Viewer',
                    };
                    final res =
                        await SheetService.updateUserPermissions(updatedUser);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(res.success
                              ? "Permissions updated for ${user['email']}"
                              : "Update failed: ${res.errorMessage}")));
                      _loadUsers();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: msmRed,
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text("SAVE CHANGES",
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showResetConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reset Dashboard?"),
        content: const Text(
            "This will set current stock calculations to zero on your dashboard.\n\nYour Google Sheet data will remain 100% safe and untouched."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL")),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade800),
              onPressed: () async {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Resetting dashboard...")));
                final success = await SheetService.resetDashboard();
                if (success) {
                  // 🚀 Centralized cleanup: Sets cutoff, clears Hive, clears Pending
                  await DataRepository.clearLocalCacheOnly();

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            "Dashboard Reset to Zero! (Strict Filter Applied)"),
                        backgroundColor: Colors.teal));
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Reset failed. Please try again."),
                        backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text("CONFIRM RESET",
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  Widget _buildSystemToolsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 48),
        const Text("System Tools",
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: textGrey)),
        const SizedBox(height: 16),
        Card(
          color: Colors.orange.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.orange.withValues(alpha: 0.2))),
          child: ListTile(
            leading:
                const Icon(Icons.restart_alt_rounded, color: Colors.orange),
            title: const Text("Soft Reset Dashboard",
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text(
                "Hide transaction history and reset stock totals to zero without deleting sheet data."),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showResetConfirmation,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      appBar: AppBar(
        title: const Text("Manage Users",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: msmRed,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: msmRed))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ..._users.map((user) {
                  final bool isApproved = user['status'] == 'Approved';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            isApproved ? Colors.green : Colors.orange,
                        child: Icon(
                            isApproved ? Icons.check : Icons.hourglass_empty,
                            color: Colors.white,
                            size: 20),
                      ),
                      title: Text(user['email'],
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("Status: ${user['status']}"),
                      trailing: TextButton(
                        onPressed: () => _showPermissionsSheet(user),
                        child: const Text("PERMISSIONS",
                            style: TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  );
                }),
                if (_users.isEmpty) const Center(child: Text("No users found")),
                _buildSystemToolsSection(),
                const SizedBox(height: 40),
              ],
            ),
    );
  }
}

// ===================== STOCK MODELS =====================

// ===================== SCREEN X: ITEM DETAIL PAGE =====================

class ItemDetailScreen extends StatefulWidget {
  final ItemGroup itemGroup;
  const ItemDetailScreen({super.key, required this.itemGroup});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  bool _isLoading = true;
  List<StockTransaction> _itemHistory = [];
  String _historyQuery = "";
  String _sizeQuery = "";
  final TextEditingController _sizeSearchCtrl = TextEditingController();
  String _sortBy = "Thickness High-Low";

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('stock_transactions_v2');
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      final all = list.map((e) => StockTransaction.fromJson(e)).toList();

      // 🚀 Apply strict global filter
      final lastReset = await DataRepository.getLastResetTimestamp();
      final DateTime resetCutoff = lastReset ?? DateTime(1900);

      _itemHistory = all
          .where((tx) {
            if (tx.isReversed) return false;
            // Strict filter condition
            if (!tx.dateTime.isAfter(resetCutoff)) return false;

            bool matchItem = tx.itemName == widget.itemGroup.itemName;
            bool matchLoc = tx.location == widget.itemGroup.location ||
                tx.toLocation == widget.itemGroup.location;
            return matchItem && matchLoc;
          })
          .toList()
          .reversed
          .toList();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.itemGroup;
    final totalMT = group.totalMT;
    final isLow = group.hasLowStock;

    return GlobalViewWrapper(
      child: Scaffold(
        backgroundColor: msmBg,
        appBar: AppBar(
          title: Text(group.itemName,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.white)),
          backgroundColor: msmRed,
          elevation: 0,
        ),
        body: _isLoading
            ? const Center(child: _MLoader(size: 80))
            : SingleChildScrollView(
                child: Column(
                  children: [
                    // Header Summary Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(30),
                            bottomRight: Radius.circular(30)),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: Offset(0, 2))
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(group.category,
                              style: const TextStyle(
                                  color: textGrey,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          GuardedMetric(
                              permission: Permissions.inventoryQuantityView,
                              value: "${totalMT.toStringAsFixed(3)} MT",
                              style: const TextStyle(
                                  color: msmRed,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          const Text("Total Current Stock",
                              style: TextStyle(color: textGrey, fontSize: 12)),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildMiniStat(
                                  "Sizes",
                                  group.variants.length.toString(),
                                  Icons.straighten),
                              _buildMiniStat(
                                  "Status",
                                  isLow ? "Low Stock" : "Normal",
                                  isLow
                                      ? Icons.warning_amber
                                      : Icons.check_circle_outline),
                            ],
                          ),
                        ],
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Quick Actions
                          const Text("Quick Actions",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: textDark)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                  child: _buildActionButton("Stock In",
                                      Icons.add_circle, Colors.teal, true)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _buildActionButton("Stock Out",
                                      Icons.remove_circle, msmRed, false)),
                            ],
                          ),

                          const SizedBox(height: 32),

                          // Size Breakdown
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Size-wise Breakdown",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: textDark)),
                              IconButton(
                                icon: const Icon(Icons.sort,
                                    size: 20, color: msmRed),
                                onPressed: () {
                                  final opts = [
                                    "Thickness High-Low",
                                    "Thickness Low-High",
                                    "Qty High-Low",
                                    "Qty Low-High"
                                  ];
                                  showModalBottomSheet(
                                      context: context,
                                      builder: (c) => Padding(
                                            padding: const EdgeInsets.all(24),
                                            child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: opts
                                                    .map((o) => ListTile(
                                                          title: Text(o,
                                                              style: TextStyle(
                                                                  fontWeight: _sortBy ==
                                                                          o
                                                                      ? FontWeight
                                                                          .bold
                                                                      : FontWeight
                                                                          .normal,
                                                                  color: _sortBy ==
                                                                          o
                                                                      ? msmRed
                                                                      : textDark)),
                                                          onTap: () {
                                                            setState(() =>
                                                                _sortBy = o);
                                                            Navigator.pop(c);
                                                          },
                                                        ))
                                                    .toList()),
                                          ));
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _sizeSearchCtrl,
                            onChanged: (v) => setState(() => _sizeQuery = v),
                            decoration: msmInputDeco("Search sizes...",
                                    prefix: const Icon(Icons.search, size: 18))
                                .copyWith(
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 12),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border:
                                    Border.all(color: Colors.grey.shade200)),
                            child: Builder(builder: (context) {
                              var filtered = applyPrioritizedSearch(_sizeQuery,
                                  widget.itemGroup.variants, (v) => v.size);

                              if (_sortBy == "Thickness High-Low") {
                                filtered.sort((a, b) =>
                                    SortingUtils.compareSizes(b.size, a.size));
                              } else if (_sortBy == "Thickness Low-High")
                                filtered.sort((a, b) =>
                                    SortingUtils.compareSizes(a.size, b.size));
                              else if (_sortBy == "Qty High-Low")
                                filtered.sort((a, b) => b.currentStockMT
                                    .compareTo(a.currentStockMT));
                              else if (_sortBy == "Qty Low-High")
                                filtered.sort((a, b) => a.currentStockMT
                                    .compareTo(b.currentStockMT));

                              if (filtered.isEmpty) {
                                return const Padding(
                                    padding: EdgeInsets.all(20),
                                    child: Center(
                                        child:
                                            Text("No sizes matching search")));
                              }

                              return ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => Divider(
                                    height: 1, color: Colors.grey.shade100),
                                itemBuilder: (context, i) {
                                  final v = filtered[i];
                                  bool low = v.currentStockMT <= v.minStock;
                                  return ListTile(
                                    title: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(v.size,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14)),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                                "Total: ${v.currentStockMT.toStringAsFixed(3)} MT",
                                                style: const TextStyle(
                                                    color: textDark,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14)),
                                            if (v.reservedStockMT > 0) ...[
                                              const SizedBox(width: 8),
                                              Text(
                                                  "(${v.availableStockMT.toStringAsFixed(3)} Avail)",
                                                  style: const TextStyle(
                                                      color: Colors.orange,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                    subtitle: Text(
                                        "Price: ₹${v.price.toStringAsFixed(0)}",
                                        style: const TextStyle(fontSize: 12)),
                                    trailing: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                            "${v.currentStockMT.toStringAsFixed(2)} MT",
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: low
                                                    ? Colors.red
                                                    : textDark)),
                                        if (low)
                                          const Text("Low Stock",
                                              style: TextStyle(
                                                  color: Colors.red,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  );
                                },
                              );
                            }),
                          ),

                          const SizedBox(height: 32),

                          // History
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Recent Movement History",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: textDark)),
                              SizedBox(
                                width: 150,
                                height: 35,
                                child: TextField(
                                  onChanged: (v) =>
                                      setState(() => _historyQuery = v),
                                  style: const TextStyle(fontSize: 12),
                                  decoration: msmInputDeco("Search history...",
                                          prefix: const Icon(Icons.search,
                                              size: 14))
                                      .copyWith(
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                        vertical: 0, horizontal: 8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Builder(builder: (context) {
                            final filteredHistory = _itemHistory
                                .where((tx) =>
                                    (tx.partyName ?? "").toLowerCase().contains(
                                        _historyQuery.toLowerCase()) ||
                                    tx.size.toLowerCase().contains(
                                        _historyQuery.toLowerCase()) ||
                                    tx.location
                                        .toLowerCase()
                                        .contains(_historyQuery.toLowerCase()))
                                .toList();

                            if (filteredHistory.isEmpty) {
                              return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 32),
                                  child: Center(
                                      child: Text(
                                          "No history found matching search.",
                                          style: TextStyle(color: textGrey))));
                            }

                            return ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: filteredHistory.take(15).length,
                              itemBuilder: (context, i) {
                                final tx = filteredHistory[i];
                                bool isIn = tx.type == 'IN';
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: Colors.grey.shade100)),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                            color: (isIn ? Colors.teal : msmRed)
                                                .withValues(alpha: 0.1),
                                            shape: BoxShape.circle),
                                        child: Icon(
                                            isIn
                                                ? Icons.arrow_downward
                                                : Icons.arrow_upward,
                                            color: isIn ? Colors.teal : msmRed,
                                            size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(tx.partyName ?? "Direct Entry",
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14)),
                                            Text(
                                                "${tx.dateTime.day}/${tx.dateTime.month}/${tx.dateTime.year} • ${tx.size} • ${tx.location}",
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: textGrey)),
                                          ],
                                        ),
                                      ),
                                      GuardedMetric(
                                          permission: Permissions
                                              .transactionsQuantityView,
                                          value:
                                              "${isIn ? '+' : '-'}${tx.qtyMT.toStringAsFixed(2)} MT",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color:
                                                  isIn ? Colors.teal : msmRed)),
                                    ],
                                  ),
                                );
                              },
                            );
                          }),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white60, size: 20),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        Text(label,
            style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ],
    );
  }

  Widget _buildActionButton(
      String label, IconData icon, Color color, bool isIn) {
    return ElevatedButton.icon(
      onPressed: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => StockTransactionScreen(
              initialType: isIn ? 'IN' : 'OUT',
              initialItem: widget.itemGroup.itemName),
        ).then((_) => _loadHistory());
      },
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
    );
  }
}

class _Shimmer extends StatefulWidget {
  final Widget child;
  const _Shimmer({required this.child});
  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.grey[300]!, Colors.grey[100]!, Colors.grey[300]!],
              stops: [
                _controller.value - 0.3,
                _controller.value,
                _controller.value + 0.3,
              ],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _StockDashboardSkeleton extends StatelessWidget {
  const _StockDashboardSkeleton();
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _Shimmer(
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              childAspectRatio: 1.5,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: List.generate(
                  5,
                  (index) => Container(
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16)))),
            ),
          ),
          const SizedBox(height: 24),
          _Shimmer(
              child: Align(
                  alignment: Alignment.centerLeft,
                  child:
                      Container(width: 100, height: 20, color: Colors.white))),
          const SizedBox(height: 16),
          _Shimmer(
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              childAspectRatio: 2.2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: List.generate(
                  2,
                  (index) => Container(
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12)))),
            ),
          ),
          const SizedBox(height: 24),
          _Shimmer(
              child: Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16)))),
        ],
      ),
    );
  }
}

// ===================== BRANDED M LOADER =====================

class _MLoader extends StatefulWidget {
  final double size;
  final Color? color;
  const _MLoader({this.size = 60, this.color});

  @override
  State<_MLoader> createState() => _MLoaderState();
}

class _MLoaderState extends State<_MLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _MPainter(
              progress: _controller.value,
              color: widget.color ?? msmRed,
            ),
          ),
        );
      },
    );
  }
}

class _MPainter extends CustomPainter {
  final double progress;
  final Color color;

  _MPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.12
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();

    // Starting point (Bottom Left)
    path.moveTo(size.width * 0.1, size.height * 0.9);
    // Left vertical line
    path.lineTo(size.width * 0.1, size.height * 0.1);
    // Middle "V" part
    path.lineTo(size.width * 0.5, size.height * 0.6);
    path.lineTo(size.width * 0.9, size.height * 0.1);
    // Right vertical line
    path.lineTo(size.width * 0.9, size.height * 0.9);

    // Animate the path drawing
    PathMetrics pathMetrics = path.computeMetrics();
    for (PathMetric pathMetric in pathMetrics) {
      Path extractPath =
          pathMetric.extractPath(0.0, pathMetric.length * progress);
      canvas.drawPath(extractPath, paint);

      // Add a subtle glowing head point
      if (progress > 0 && progress < 1.0) {
        final pos = pathMetric
            .getTangentForOffset(pathMetric.length * progress)!
            .position;
        canvas.drawCircle(
            pos, paint.strokeWidth * 0.6, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke; // Reset for next iteration or frame
      }
    }

    // Second pass for a subtle pulse/shadow effect
    if (progress > 0.8) {
      final opacity = (progress - 0.8) * 5; // Fade in at the end
      final pulsePaint = Paint()
        ..color = color.withValues(
            alpha: 0.2 * (1.0 - opacity >= 0 ? 1.0 - opacity : 0))
        ..strokeWidth = paint.strokeWidth * 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, pulsePaint);
    }
  }

  @override
  bool shouldRepaint(_MPainter oldDelegate) => oldDelegate.progress != progress;
}

/* ===================== NEW: ITEM QUANTITY SCREEN ===================== */

class ItemQuantityScreen extends StatefulWidget {
  const ItemQuantityScreen({super.key});

  @override
  State<ItemQuantityScreen> createState() => _ItemQuantityScreenState();
}

class _ItemQuantityScreenState extends State<ItemQuantityScreen> {
  bool _isLoading = true;
  List<ItemGroup> _allGroups = [];
  List<ItemGroup> _filteredGroups = [];
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = "";
  String _sortBy =
      "Priority"; // "Priority", "Name A-Z", "Name Z-A", "Qty High-Low", "Qty Low-High"

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  double _yardTotalMT = 0.0;
  double _factoryTotalMT = 0.0;
  double _totalInMT = 0;
  double _totalOutMT = 0;

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('stock_transactions_v2');
    List<StockTransaction> txs = [];
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      txs = list.map((e) => StockTransaction.fromJson(e)).toList();
    }

    final data = await DataRepository.getSheetDataAsync(null);
    final List<dynamic> items = data['items'] ?? [];

    _yardTotalMT = 0;
    _factoryTotalMT = 0;
    _totalInMT = 0;
    _totalOutMT = 0;

    for (var tx in txs) {
      final txType = tx.type.toUpperCase().trim();
      if (tx.isReversed || txType == 'CANCELLED' || txType == 'CANCELED') {
        continue;
      }
      if (tx.type == 'IN') {
        _totalInMT += tx.qtyMT;
      } else {
        _totalOutMT += tx.qtyMT;
      }
    }

    final Set<String> uniqueItemSizes = {};
    for (var tx in txs) {
      final txType = tx.type.toUpperCase().trim();
      if (tx.isReversed || txType == 'CANCELLED' || txType == 'CANCELED') {
        continue;
      }
      uniqueItemSizes.add("${tx.itemName}|${tx.size}");
    }

    final Map<String, double> sizePrices = {};
    for (var item in items) {
      final name = item['name']?.toString().trim() ?? '';
      final sizes = item['sizes'] as List? ?? [];
      for (var s in sizes) {
        final label = s['label'] ?? '';
        final price = (s['sd'] as num?)?.toDouble() ?? 0.0;
        sizePrices["$name|$label"] = price;
        uniqueItemSizes.add("$name|$label");
      }
    }

    Map<String, ItemGroup> groups = {};

    for (var key in uniqueItemSizes) {
      final parts = key.split('|');
      if (parts.length < 2) continue;
      final name = parts[0];
      final label = parts[1];
      final price = sizePrices[key] ?? 0.0;

      ItemVariant vYard = ItemVariant(
          itemName: name,
          category: name,
          size: label,
          currentStockMT: 0,
          minStock: 5,
          price: price,
          location: 'YARD');
      ItemVariant vFactory = ItemVariant(
          itemName: name,
          category: name,
          size: label,
          currentStockMT: 0,
          minStock: 5,
          price: price,
          location: 'FACTORY');

      for (var tx in txs) {
        final txType = tx.type.toUpperCase().trim();
        if (tx.isReversed || txType == 'CANCELLED' || txType == 'CANCELED') {
          continue;
        }
        if (tx.itemName != name || tx.size != label) continue;
        final txLoc = StockUtils.normalizeLocation(tx.location);
        final txToLoc = StockUtils.normalizeLocation(tx.toLocation ?? '');

        // Process YARD
        if (tx.type == 'TRANSFER') {
          if (txLoc == 'YARD') vYard.currentStockMT -= tx.qtyMT;
          if (txToLoc == 'YARD') vYard.currentStockMT += tx.qtyMT;
        } else if (txLoc == 'YARD') {
          if (tx.type == 'IN' ||
              tx.type == 'RETURN' ||
              tx.type == 'OPENING' ||
              tx.type == 'ADJUSTMENT') {
            vYard.currentStockMT += tx.qtyMT;
          } else if (tx.type == 'OUT') {
            vYard.currentStockMT -= tx.qtyMT;
          } else if (tx.type == 'RESERVE') {
            vYard.reservedStockMT += tx.qtyMT;
          }
        }

        // Process FACTORY
        if (tx.type == 'TRANSFER') {
          if (txLoc == 'FACTORY') vFactory.currentStockMT -= tx.qtyMT;
          if (txToLoc == 'FACTORY') vFactory.currentStockMT += tx.qtyMT;
        } else if (txLoc == 'FACTORY') {
          if (tx.type == 'IN' ||
              tx.type == 'RETURN' ||
              tx.type == 'OPENING' ||
              tx.type == 'ADJUSTMENT') {
            vFactory.currentStockMT += tx.qtyMT;
          } else if (tx.type == 'OUT') {
            vFactory.currentStockMT -= tx.qtyMT;
          } else if (tx.type == 'RESERVE') {
            vFactory.reservedStockMT += tx.qtyMT;
          }
        }
      }

      if (vYard.currentStockMT < 0.0) vYard.currentStockMT = 0.0;
      if (vFactory.currentStockMT < 0.0) vFactory.currentStockMT = 0.0;

      if (vYard.currentStockMT > 0) _yardTotalMT += vYard.currentStockMT;
      if (vFactory.currentStockMT > 0) {
        _factoryTotalMT += vFactory.currentStockMT;
      }

      // Group by Name (Location)
      final yardKey = "$name (YARD)";
      if (vYard.currentStockMT > 0) {
        if (!groups.containsKey(yardKey)) {
          groups[yardKey] = ItemGroup(name, name, location: 'YARD');
        }
        groups[yardKey]!.variants.add(vYard);
      }

      final factKey = "$name (FACTORY)";
      if (vFactory.currentStockMT > 0) {
        if (!groups.containsKey(factKey)) {
          groups[factKey] = ItemGroup(name, name, location: 'FACTORY');
        }
        groups[factKey]!.variants.add(vFactory);
      }
    }
    for (var group in groups.values) {
      group.variants.sort((a, b) => SortingUtils.compareSizes(a.size, b.size));
    }
    if (mounted) {
      setState(() {
        _allGroups = groups.values.toList();
        _filteredGroups = _allGroups;
        _isLoading = false;
      });
    }
  }

  void _filterItems(String query) {
    setState(() {
      _searchQuery = query;
      _applyFilterAndSort();
    });
  }

  void _applyFilterAndSort() {
    List<ItemGroup> filtered = applyPrioritizedSearch(
        _searchQuery, _allGroups, (g) => "${g.itemName} ${g.category}");

    if (_sortBy == "Priority") {
      filtered.sort(
          (a, b) => SortingUtils.compareCategories(a.itemName, b.itemName));
    } else if (_sortBy == "Name A-Z") {
      filtered.sort((a, b) =>
          a.itemName.toLowerCase().compareTo(b.itemName.toLowerCase()));
    } else if (_sortBy == "Name Z-A") {
      filtered.sort((a, b) =>
          b.itemName.toLowerCase().compareTo(a.itemName.toLowerCase()));
    } else if (_sortBy == "Qty High-Low") {
      filtered.sort((a, b) => b.totalMT.compareTo(a.totalMT));
    } else if (_sortBy == "Qty Low-High") {
      filtered.sort((a, b) => a.totalMT.compareTo(b.totalMT));
    }

    setState(() => _filteredGroups = filtered);
  }

  void _showSortSheet() {
    final opts = [
      "Priority",
      "Name A-Z",
      "Name Z-A",
      "Qty High-Low",
      "Qty Low-High"
    ];
    showModalBottomSheet(
        context: context,
        builder: (c) => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text("Sort Items",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 16),
                ...opts.map((o) => ListTile(
                      title: Text(o,
                          style: TextStyle(
                              fontWeight: _sortBy == o
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: _sortBy == o ? msmRed : textDark)),
                      trailing: _sortBy == o
                          ? const Icon(Icons.check_circle, color: msmRed)
                          : null,
                      onTap: () {
                        setState(() => _sortBy = o);
                        _applyFilterAndSort();
                        Navigator.pop(c);
                      },
                    )),
              ]),
            ));
  }

  @override
  Widget build(BuildContext context) {
    return GlobalViewWrapper(
      child: Scaffold(
        backgroundColor: msmBg,
        appBar: AppBar(
          title: const Text("Item Quantity",
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.white)),
          backgroundColor: msmRed,
          elevation: 0,
        ),
        body: Column(
          children: [
            // Total Summary Grid
            Container(
              color: msmRed,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 2.5,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                children: [
                  _buildSummaryCard(
                      "Yard Stock",
                      "${_yardTotalMT.toStringAsFixed(2)} MT",
                      Icons.warehouse_rounded,
                      Colors.indigo),
                  _buildSummaryCard(
                      "Factory Stock",
                      "${_factoryTotalMT.toStringAsFixed(2)} MT",
                      Icons.factory_rounded,
                      Colors.teal),
                  _buildSummaryCard(
                      "Total In",
                      "${_totalInMT.toStringAsFixed(2)} MT",
                      Icons.arrow_downward_rounded,
                      Colors.green),
                  _buildSummaryCard(
                      "Total Out",
                      "${_totalOutMT.toStringAsFixed(2)} MT",
                      Icons.arrow_upward_rounded,
                      Colors.white,
                      isWhite: true),
                ],
              ),
            ),

            Container(
              color: msmRed,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: _filterItems,
                        decoration: InputDecoration(
                          hintText: "Search items...",
                          prefixIcon: const Icon(Icons.search, color: textGrey),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 14),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    _filterItems("");
                                  })
                              : null,
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1, indent: 12, endIndent: 12),
                    IconButton(
                        icon: const Icon(Icons.sort, color: textGrey),
                        onPressed: _showSortSheet),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: _MLoader(size: 80))
                  : _filteredGroups.isEmpty
                      ? const Center(
                          child: Text("No items found",
                              style: TextStyle(color: textGrey)))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredGroups.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final group = _filteredGroups[index];
                            final isYard = group.location == 'YARD';
                            final isOut = group.totalMT <= 0;
                            return Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                title: Text(group.itemName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: textDark)),
                                subtitle: Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: isYard
                                                ? Colors.indigo.shade50
                                                : Colors.teal.shade50,
                                            borderRadius:
                                                BorderRadius.circular(4)),
                                        child: Text(group.location ?? '',
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: isYard
                                                    ? Colors.indigo
                                                    : Colors.teal)),
                                      ),
                                    ],
                                  ),
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                        "${group.totalMT.toStringAsFixed(3)} MT",
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: textDark)),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color:
                                            isOut ? Colors.red : Colors.green,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(isOut ? "OUT" : "OK",
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                                onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) => ScreenGate(
                                              canAccess: (s) => AccessGuard.can(
                                                  Permissions
                                                      .screensStockDetail),
                                              screenName: group.itemName,
                                              child: ItemSizeDetailsScreen(
                                                  itemGroup: group),
                                            ))),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
      String title, String value, IconData icon, Color color,
      {bool isWhite = false}) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isWhite ? Colors.white.withValues(alpha: 0.2) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
                color: isWhite ? Colors.white24 : color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: isWhite ? Colors.white : color, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value,
                    style: TextStyle(
                        color: isWhite ? Colors.white : textDark,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
                Text(title,
                    style: TextStyle(
                        color: isWhite ? Colors.white70 : textGrey,
                        fontSize: 8,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ===================== NEW: ITEM SIZE DETAILS SCREEN ===================== */

class ItemSizeDetailsScreen extends StatefulWidget {
  final ItemGroup itemGroup;
  const ItemSizeDetailsScreen({super.key, required this.itemGroup});

  @override
  State<ItemSizeDetailsScreen> createState() => _ItemSizeDetailsScreenState();
}

class _ItemSizeDetailsScreenState extends State<ItemSizeDetailsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = "";
  String _sortBy = "Thickness High-Low";

  @override
  Widget build(BuildContext context) {
    // Filter and Sort variants directly
    var filteredVariants = widget.itemGroup.variants;

    // Filter
    if (_query.isNotEmpty) {
      filteredVariants = filteredVariants
          .where((v) => v.size.toLowerCase().contains(_query.toLowerCase()))
          .toList();
    }

    // Sort
    if (_sortBy == "Thickness High-Low") {
      filteredVariants
          .sort((a, b) => SortingUtils.compareSizes(b.size, a.size));
    } else if (_sortBy == "Thickness Low-High")
      filteredVariants
          .sort((a, b) => SortingUtils.compareSizes(a.size, b.size));
    else if (_sortBy == "Alpha A-Z")
      filteredVariants.sort((a, b) => a.size.compareTo(b.size));
    else if (_sortBy == "Qty High-Low")
      filteredVariants
          .sort((a, b) => b.currentStockMT.compareTo(a.currentStockMT));

    return GlobalViewWrapper(
      child: Scaffold(
        backgroundColor: msmBg,
        appBar: AppBar(
          title: const Text("Size Details",
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.white)),
          backgroundColor: msmRed,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.sort, color: Colors.white),
              onPressed: () {
                final opts = [
                  "Thickness High-Low",
                  "Thickness Low-High",
                  "Alpha A-Z",
                  "Qty High-Low"
                ];
                showModalBottomSheet(
                    context: context,
                    builder: (c) => Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: opts
                                  .map((o) => ListTile(
                                        title: Text(o,
                                            style: TextStyle(
                                                fontWeight: _sortBy == o
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                color: _sortBy == o
                                                    ? msmRed
                                                    : textDark)),
                                        onTap: () {
                                          setState(() => _sortBy = o);
                                          Navigator.pop(c);
                                        },
                                      ))
                                  .toList()),
                        ));
              },
            )
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              color: msmRed,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: msmInputDeco("Search sizes...",
                        prefix: const Icon(Icons.search, color: textGrey))
                    .copyWith(
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 2))
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.itemGroup.itemName,
                            style: const TextStyle(
                                color: msmRed,
                                fontSize: 24,
                                fontWeight: FontWeight.bold)),
                        Text(widget.itemGroup.location ?? '',
                            style: const TextStyle(
                                color: textGrey,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text("Total Stock",
                          style: TextStyle(color: textGrey, fontSize: 12)),
                      Text("${widget.itemGroup.totalMT.toStringAsFixed(3)} MT",
                          style: const TextStyle(
                              color: textDark,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Text("Available Sizes",
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textDark)),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: filteredVariants.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, color: Color(0xFFEEEEEE)),
                itemBuilder: (context, index) {
                  final v = filteredVariants[index];
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(v.size,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: textDark)),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: (v.location == 'YARD'
                                          ? Colors.indigo
                                          : (v.location == 'FACTORY'
                                              ? Colors.teal
                                              : Colors.blueGrey))
                                      .shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: (v.location == 'YARD'
                                              ? Colors.indigo
                                              : (v.location == 'FACTORY'
                                                  ? Colors.teal
                                                  : Colors.blueGrey))
                                          .shade100)),
                              child: Text(v.location,
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: v.location == 'YARD'
                                          ? Colors.indigo
                                          : (v.location == 'FACTORY'
                                              ? Colors.teal
                                              : Colors.blueGrey.shade700))),
                            ),
                          ],
                        ),
                        GuardedMetric(
                          permission: Permissions.inventoryQuantityView,
                          value: "${v.currentStockMT.toStringAsFixed(3)} MT",
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: msmRed),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersistentHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _PersistentHeaderDelegate({required this.child});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  double get maxExtent => 80.0;

  @override
  double get minExtent => 80.0;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return true;
  }
}
