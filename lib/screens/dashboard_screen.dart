import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user_session_notifier.dart';
import '../widgets/m_loader.dart';
import '../constants/app_colors.dart';
import '../services/data_repository.dart';
import '../widgets/global_view_wrapper.dart';
import '../models/stock_models.dart';
import '../main.dart';
import 'quick_rate_calculator_screen.dart';
import 'manage_users_screen.dart';
import 'calculator_screen.dart';
import 'sauda_booking_screen.dart';
import 'sauda_report_screen.dart'; // Contains Sauda Report and VendorPurchaseReportScreen
import 'professional_reports_screen.dart';
import 'sales_document_center_screen.dart';
import 'main_inventory_shell.dart';
import 'master_size_management_screen.dart';
import 'dealer_stock_share_screen.dart';
import '../models/stock_role.dart';
import '../widgets/screen_gate.dart';

import '../widgets/dashboard_sliver_header.dart';
import '../widgets/dashboard/executive_telemetry_header.dart';
import '../widgets/dashboard/compact_kpi_ribbon.dart';
import '../widgets/dashboard/unified_stock_distribution_card.dart';
import '../widgets/dashboard/enterprise_quick_actions_grid.dart';
import '../services/auth_service.dart';
import '../services/app_update_service.dart';

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

  final String _selectedTab = 'Overview';
  static const Color appRed = Color(0xFFD41F2A);
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
    _permissionPollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshCurrentUserData(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          AppUpdateService.checkForUpdates(context);
        }
      });
    });
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

  Future<void> _refreshCurrentUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('user_email');
      if (email == null || email.isEmpty) return;

      final previousSnapshot = UserSessionNotifier.instance.value;
      await DataRepository.syncCurrentUser(email);

      if (!mounted) return;
      final changed = UserSessionNotifier.refreshFromSession();
      if (!changed) return;
      if (mounted) setState(() {});
      final newSnapshot = UserSessionNotifier.instance.value;

      final screenMap = {
        'Sauda Book Only': 'Sauda Book',
        'Quotation Only': 'Quotation',
        'Netrate Calc Only': 'Netrate Calc',
        'Stock Inventory Only': 'Stock Inventory',
      };

      for (final entry in screenMap.entries) {
        final hadAccess = previousSnapshot.canAccess(entry.key);
        final hasAccess = newSnapshot.canAccess(entry.key);
        if (hadAccess && !hasAccess) {
          appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  '🔒 Your access permissions have been updated by an Administrator.',
                  style: TextStyle(color: Colors.white),
                ),
                backgroundColor: Colors.red.shade700,
                duration: const Duration(seconds: 5),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('Permission sync error: $e');
    }
  }

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
    setState(() {
      _isSyncing = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Syncing latest data..."),
        duration: Duration(seconds: 1)));

    try {
      await DataRepository.syncSheetData(context, force: true);
      if (!mounted) return;
      await DataRepository.refreshAllStockData(forceRefresh: true);
      if (!mounted) return;
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

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    try {
      await _googleSignIn.signOut();
      await _googleSignIn.disconnect();
    } catch (e) {
      debugPrint("Logout Error: $e");
    }
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (Route<dynamic> route) => false);
    }
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
          return _ProfileBottomSheetContent(
            initialName: initialName,
            initialPhone: initialPhone,
            email: _email,
            photoUrl: _currentUser?.photoUrl,
            onSave: (newName, newPhone) async {
              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              await _saveProfileData(newName, newPhone);
              if (!mounted) return;
              nav.pop();
              messenger.showSnackBar(const SnackBar(
                  content: Text("✅ Profile Updated"),
                  backgroundColor: Colors.green));
            },
            onLogout: () {
              Navigator.pop(context);
              _handleLogout();
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
          backgroundColor: Color(0xFFFFF8F8),
          body: Center(child: MLoader(size: 80, color: msmRed)));
    }

    return GlobalViewWrapper(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 900;
          final isMobile = constraints.maxWidth < 600;

          if (isMobile) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                textScaler:
                    TextScaler.linear(mq.textScaler.scale(1.0).clamp(1.0, 1.2)),
              ),
              child: Scaffold(
                backgroundColor: const Color(0xFFF8F9FB),
                body: _buildMobileLayout(),
              ),
            );
          }

          // Desktop/Tablet Executive ERP Command Center Layout
          Widget rootContent = Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            body: SafeArea(
              child: RefreshIndicator(
                onRefresh: _handleSync,
                color: appRed,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                      20, 20, 20, isDesktop ? 24 : 32),
                  child: ListenableBuilder(
                    listenable: Listenable.merge([
                      DataRepository.currentUserNotifier,
                      UserSessionNotifier.instance,
                    ]),
                    builder: (context, _) {
                      final currentUser =
                          DataRepository.currentUserNotifier.value;
                      final bool isAdmin = (currentUser != null &&
                              currentUser.isAdmin) ||
                          UserSession.currentRole == StockRole.ADMIN ||
                          UserSessionNotifier.instance.value.role ==
                              StockRole.ADMIN;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildExecutiveTelemetryHeader(),
                          const SizedBox(height: 16),
                          if (isAdmin) ...[
                            _buildKpiRibbon(),
                            const SizedBox(height: 16),
                            _buildStockDistributionCard(),
                            const SizedBox(height: 16),
                          ],
                          const EnterpriseQuickActionsGrid(),
                          const SizedBox(height: 32),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          return rootContent;
        },
      ),
    );
  }

  Widget _buildMobileLayout() {
    return RefreshIndicator(
      onRefresh: _handleSync,
      edgeOffset: MediaQuery.of(context).padding.top +
          88, // Start below the collapsed header
      color: appRed,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          DashboardSliverHeader(
            userName: _effectiveDisplayName(),
            companyName: "MSM One",
            isSyncing: _isSyncing,
            onRefresh: _handleSync,
            onProfileTap: _showProfile,
            onLogout: _handleLogout,
          ),
          SliverSafeArea(
            top: false,
            bottom: true,
            sliver: SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildMobileActionsGrid(),
                  const SizedBox(height: 28),
                  const Text(
                    "Support & Help",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F1A1A),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildMobileSupportCard(),
                  const SizedBox(height: 20),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // _buildMobileHeader is now replaced by DashboardHeader widget

  Widget _buildMobileActionsGrid() {
    return ValueListenableBuilder<PermissionSnapshot>(
      valueListenable: UserSessionNotifier.instance,
      builder: (context, snap, _) {
        final actions = [
          if (snap.canAccessQuotation)
            _MobileActionData(
              title: "Quotation",
              icon: Icons.description_rounded,
              color: appRed,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ScreenGate(
                            canAccess: (s) => s.canAccessQuotation,
                            screenName: "Quotation",
                            child:
                                const CalculatorScreen(isQuotationMode: true),
                          ))),
            ),
          if (snap.canAccessCalculator)
            _MobileActionData(
              title: "Netrate Calc",
              icon: Icons.calculate_outlined,
              color: appRed,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ScreenGate(
                            canAccess: (s) => s.canAccessCalculator,
                            screenName: "Netrate Calc",
                            child:
                                const CalculatorScreen(isQuotationMode: false),
                          ))),
            ),
          if (snap.canAccessSaudaBooking)
            _MobileActionData(
              title: "Sauda Book",
              icon: Icons.menu_book_rounded,
              color: appRed,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ScreenGate(
                            canAccess: (s) => s.canAccessSaudaBooking,
                            screenName: "Sauda Book",
                            child: const SaudaBookingScreen(),
                          ))),
            ),
          if (snap.canAccessVendorPurchaseScreen)
            _MobileActionData(
              title: "Vendor Purchase",
              icon: Icons.local_shipping_outlined,
              color: appRed,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ScreenGate(
                            canAccess: (s) => s.canAccessVendorPurchaseScreen,
                            screenName: "Vendor Purchase",
                            child: const VendorPurchaseReportScreen(),
                          ))),
            ),
          if (snap.canAccessStockInventory)
            _MobileActionData(
              title: "Inventory In & Out",
              icon: Icons.inventory_2_rounded,
              color: appRed,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ScreenGate(
                            canAccess: (s) => s.canAccessStockInventory,
                            screenName: "Inventory In & Out",
                            child: const MainInventoryShell(),
                          ))),
            ),
          if (snap.canAccessStockInventory)
            _MobileActionData(
              title: "Stock Sheet",
              icon: Icons.share_rounded,
              color: appRed,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ScreenGate(
                            canAccess: (s) => s.canAccessStockInventory,
                            screenName: "Stock Sheet",
                            child: const DealerStockShareScreen(),
                          ))),
            ),
          if (snap.canAccessReports)
            _MobileActionData(
              title: "Reports",
              icon: Icons.bar_chart_rounded,
              color: appRed,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ScreenGate(
                            canAccess: (s) => s.canAccessReports,
                            screenName: "Reports",
                            child: const ProfessionalReportsScreen(),
                          ))),
            ),
          if (snap.canAccessSampleRate)
            _MobileActionData(
              title: "Sample Rate",
              icon: Icons.bolt_rounded,
              color: appRed,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ScreenGate(
                            canAccess: (s) => s.canAccessSampleRate,
                            screenName: "Sample Rate",
                            child: const SampleRateCalcScreen(),
                          ))),
            ),
          if (snap.role == StockRole.ADMIN || snap.canAccessUsers)
            _MobileActionData(
              title: "Users",
              icon: Icons.people_rounded,
              color: appRed,
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ScreenGate(
                            canAccess: (s) =>
                                s.role == StockRole.ADMIN || s.canAccessUsers,
                            screenName: "Users",
                            child: const ManageUsersScreen(),
                          ))),
            ),
          if (snap.role == StockRole.ADMIN)
            _MobileActionData(
              title: "Sales Document Center",
              icon: Icons.assignment_turned_in_outlined,
              color: const Color(0xFF1A237E),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ScreenGate(
                          canAccess: (s) => s.role == StockRole.ADMIN,
                          screenName: "Sales Document Center",
                          child: const SalesDocumentCenterScreen(),
                        )),
              ),
            ),
          if (snap.canAccessMasterSize)
            _MobileActionData(
              title: "Master Size",
              icon: Icons.rule_rounded,
              color: appRed,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ScreenGate(
                          canAccess: (s) => s.canAccessMasterSize,
                          screenName: "Master Size",
                          child: const MasterSizeManagementScreen(),
                        )),
              ),
            ),
        ];

        return LayoutBuilder(
          builder: (context, constraints) {
            final double textScale =
                MediaQuery.of(context).textScaler.scale(1.0);
            final double cardWidth = (constraints.maxWidth - 16) / 2;
            final double estimatedCardHeight =
                28 + 44 + 10 + (12 * textScale * 1.4 * 2) + 28;
            final double ratio =
                (cardWidth / estimatedCardHeight).clamp(0.85, 1.35);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: ratio,
              ),
              itemCount: actions.length,
              itemBuilder: (context, i) => _buildMobileActionCard(actions[i]),
            );
          },
        );
      },
    );
  }

  Widget _buildMobileActionCard(_MobileActionData data) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: data.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(data.icon, color: data.color, size: 26),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: Text(
                    data.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: textDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileSupportCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showContact,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: const Color(0xFFBAE6FD), width: 1),
                  ),
                  child: const Icon(Icons.support_agent_rounded,
                      color: Color(0xFF0284C7), size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Contact Support",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        "Need assistance? We are here to help.",
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    size: 12, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- 2. EXECUTIVE COMMAND CENTER BUILDERS (Desktop/Tablet) ---

  Widget _buildExecutiveTelemetryHeader() {
    return StreamBuilder<List<ItemVariant>>(
      stream: DataRepository.getSupabaseStockStream(),
      builder: (context, snapshot) {
        final inventory =
            snapshot.data ?? DataRepository.inventoryListNotifier.value;
        int attentionCount = 0;
        for (final v in inventory) {
          if (v.currentStockMT <= 0 || v.currentStockMT < v.minStock) {
            attentionCount++;
          }
        }

        return ExecutiveTelemetryHeader(
          userName: _effectiveDisplayName(),
          subtitle: 'MSM Yard Inventory & Operations',
          isSupabaseLive: snapshot.connectionState != ConnectionState.waiting,
          isSyncing: _isSyncing,
          locationLabel: 'Yard: All',
          attentionCount: attentionCount,
          onRefresh: _handleSync,
          onProfileTap: _showProfile,
          onAttentionTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const ReportsDashboardScreen(initialTabId: 'low'),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildKpiRibbon() {
    return StreamBuilder<List<ItemVariant>>(
      stream: DataRepository.getSupabaseStockStream(),
      builder: (context, snapshot) {
        final inventory =
            snapshot.data ?? DataRepository.inventoryListNotifier.value;
        final totalStock =
            inventory.fold(0.0, (sum, item) => sum + item.netStockMt);

        return ListenableBuilder(
          listenable: Listenable.merge([
            DataRepository.allTransactionsNotifier,
            DataRepository.todayOutNotifier,
          ]),
          builder: (context, _) {
            final txns = DataRepository.allTransactionsNotifier.value;
            final today = DateTime.now();
            final todayStart = DateTime(today.year, today.month, today.day);
            double todayIn = 0;
            double todayOut = DataRepository.todayOutNotifier.value;

            for (final tx in txns) {
              if (tx.isReversed) continue;
              if (!tx.dateTime.isBefore(todayStart)) {
                final typeUpper = tx.type.trim().toUpperCase();
                if ([
                  'IN',
                  'INWARD',
                  'RETURN',
                  'ADJUSTMENT',
                  'OPENING',
                  'OPENING_STOCK'
                ].contains(typeUpper)) {
                  todayIn += tx.qtyMT;
                }
              }
            }

            int attentionCount = 0;
            for (final v in inventory) {
              if (v.currentStockMT <= 0 || v.currentStockMT < v.minStock) {
                attentionCount++;
              }
            }

            return CompactKpiRibbon(
              totalStockMT: totalStock,
              todayInwardMT: todayIn,
              todayOutwardMT: todayOut,
              attentionDeficitCount: attentionCount,
              onTotalStockTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const ReportsDashboardScreen(initialTabId: 'movement'),
                  ),
                );
              },
              onInwardTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const ReportsDashboardScreen(initialTabId: 'today'),
                  ),
                );
              },
              onOutwardTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const ReportsDashboardScreen(initialTabId: 'today'),
                  ),
                );
              },
              onAttentionTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const ReportsDashboardScreen(initialTabId: 'low'),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildStockDistributionCard() {
    return StreamBuilder<List<ItemVariant>>(
      stream: DataRepository.getSupabaseStockStream(),
      builder: (context, snapshot) {
        final inventory =
            snapshot.data ?? DataRepository.inventoryListNotifier.value;
        final totalStock =
            inventory.fold(0.0, (sum, item) => sum + item.netStockMt);
        final yardStock = inventory
            .where((item) =>
                item.location == 'YARD' ||
                item.location == 'ALL' ||
                item.location.trim().isEmpty)
            .fold(0.0, (sum, item) => sum + item.currentStockMT);
        final factoryStock = inventory
            .where((item) => item.location == 'FACTORY')
            .fold(0.0, (sum, item) => sum + item.currentStockMT);

        return UnifiedStockDistributionCard(
          yardStockMT: yardStock,
          factoryStockMT: factoryStock,
          totalStockMT: totalStock,
          onYardTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const ReportsDashboardScreen(initialTabId: 'movement'),
              ),
            );
          },
          onFactoryTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const ReportsDashboardScreen(initialTabId: 'movement'),
              ),
            );
          },
        );
      },
    );
  }
}

class _ProfileBottomSheetContent extends StatefulWidget {
  final String initialName;
  final String initialPhone;
  final String email;
  final String? photoUrl;
  final Future<void> Function(String, String) onSave;
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
  _ProfileBottomSheetContentState createState() =>
      _ProfileBottomSheetContentState();
}

class _ProfileBottomSheetContentState
    extends State<_ProfileBottomSheetContent> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _phoneController = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
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
            controller: _nameController,
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
            controller: _phoneController,
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
                    widget.onSave(_nameController.text, _phoneController.text),
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

class _MobileActionData {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  _MobileActionData({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}
