import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:msm_calc/providers/user_provider.dart';
import 'package:msm_calc/widgets/authentication_guard.dart';
import 'package:msm_calc/screens/registration_screen.dart';
import 'package:msm_calc/models/app_user.dart';
import 'package:msm_calc/services/supabase_service.dart';

// Mock SupabaseClient to bypass network calls in tests
class MockSupabaseClient extends Fake implements SupabaseClient {
  final MockGoTrueClient mockAuth = MockGoTrueClient();
  @override
  GoTrueClient get auth => mockAuth;
}

class MockGoTrueClient extends Fake implements GoTrueClient {
  User? mockUser;
  @override
  User? get currentUser => mockUser;
}

void main() {
  late MockSupabaseClient mockClient;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockClient = MockSupabaseClient();
    SupabaseService.mockClient = mockClient;
  });

  tearDown(() {
    SupabaseService.mockClient = null;
  });

  group('AuthenticationGuard Widget Tests', () {
    testWidgets('shows loading indicator during initialization',
        (WidgetTester tester) async {
      final userProvider = UserProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<UserProvider>.value(
            value: userProvider,
            child: const AuthenticationGuard(
              child: Scaffold(body: Text('Protected Dashboard')),
            ),
          ),
        ),
      );

      // Verify that the loading indicator is displayed and dashboard is pointer-blocked
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Protected Dashboard'), findsOneWidget);

      // Verify layout has an IgnorePointer ignoring events
      final ignorePointerFinder = find.byWidgetPredicate(
        (widget) => widget is IgnorePointer && widget.ignoring == true,
      );
      expect(ignorePointerFinder, findsAtLeastNWidgets(1));
    });

    testWidgets(
        'shows RegistrationScreen when user is authenticated with Supabase but not in public.users DB',
        (WidgetTester tester) async {
      // Simulate Google auth is active but user is missing from UserProvider
      mockClient.mockAuth.mockUser = User(
        id: 'user-id',
        appMetadata: {},
        userMetadata: {},
        aud: 'aud',
        createdAt: DateTime.now().toIso8601String(),
      );

      final userProvider = UserProvider();
      // Emulate auth initialization is complete but user is null
      userProvider.markInitialized();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<UserProvider>.value(
            value: userProvider,
            child: const AuthenticationGuard(
              child: Scaffold(body: Text('Protected Dashboard')),
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify that the RegistrationScreen lock is active and protected content is not shown
      expect(find.byType(RegistrationScreen), findsOneWidget);
      expect(find.text('Protected Dashboard'), findsNothing);
    });

    testWidgets(
        'shows RegistrationScreen when user is authenticated but not approved',
        (WidgetTester tester) async {
      final userProvider = UserProvider();

      // Simulate user state set but status is unapproved (e.g. pending)
      final pendingUser = AppUser(
        email: 'test@msm.com',
        role: 'staff',
        status: 'pending',
        allowedActions: [],
      );

      userProvider.setUser(pendingUser);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<UserProvider>.value(
            value: userProvider,
            child: const AuthenticationGuard(
              child: Scaffold(body: Text('Protected Dashboard')),
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify that the RegistrationScreen lock is active and protected content is not shown
      expect(find.byType(RegistrationScreen), findsOneWidget);
      expect(find.text('Protected Dashboard'), findsNothing);
    });

    testWidgets('passes child through when user is approved',
        (WidgetTester tester) async {
      final userProvider = UserProvider();

      final approvedUser = AppUser(
        email: 'admin@msm.com',
        role: 'admin',
        status: 'approved',
        allowedActions: [],
      );

      userProvider.setUser(approvedUser);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<UserProvider>.value(
            value: userProvider,
            child: const AuthenticationGuard(
              child: Scaffold(body: Text('Protected Dashboard')),
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify that the user successfully bypassed the guard
      expect(find.text('Protected Dashboard'), findsOneWidget);
      expect(find.byType(RegistrationScreen), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
