import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_keys.dart';
import 'config/app_config.dart';
import 'auth/session_controller.dart';
import 'screens/arrivals_screen.dart';
import 'screens/brands_screen.dart';
import 'screens/clients_screen.dart';
import 'screens/debts_screen.dart';
import 'screens/employees_add_screen.dart';
import 'screens/employees_edit_screen.dart';
import 'screens/employees_screen.dart';
import 'screens/employees_view_screen.dart';
import 'screens/exchange_rate_screen.dart';
import 'screens/expenses_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/moderators_add_screen.dart';
import 'screens/moderators_screen.dart';
import 'screens/offline_queue_screen.dart';
import 'screens/platform_dashboard_screen.dart';
import 'screens/platform_users_screen.dart';
import 'screens/privacy_policy_screen.dart';
import 'screens/product_details_screen.dart';
import 'screens/notifications_settings_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/referral_screen.dart';
import 'screens/support_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/returns_screen.dart';
import 'screens/sales_screen.dart';
import 'screens/stores_screen.dart';
import 'screens/tariffs_screen.dart';
import 'screens/transfers_screen.dart';
import 'screens/warehouse_screen.dart';
import 'services/api_client.dart';
import 'services/auth_storage.dart';
import 'services/iap_service.dart';
import 'services/web_tab_resume.dart';
import 'utils/platform_info.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'utils/permissions.dart';
import 'widgets/businessman_section_gate.dart';
import 'widgets/skeleton_loading.dart';

Widget _guarded(String sectionKey, Widget child) =>
    BusinessmanSectionGate(sectionKey: sectionKey, child: child);

class TojirApp extends StatelessWidget {
  const TojirApp({super.key});

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      debugPrint('Tojir API: ${AppConfig.apiBase}');
    }
    final storage = AuthStorage();
    final api = ApiClient(storage);
    final session = SessionController(storage, api);
    final theme = ThemeController();

    return MultiProvider(
      providers: [
        Provider<AuthStorage>.value(value: storage),
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<SessionController>.value(value: session),
        ChangeNotifierProvider<ThemeController>.value(value: theme),
      ],
      builder: (ctx, _) => MaterialApp(
        scaffoldMessengerKey: appScaffoldMessengerKey,
        title: 'Tojir',
        debugShowCheckedModeBanner: false,
        onGenerateRoute: (settings) {
          final n = settings.name;
          if (n != null && n.startsWith('/warehouse/product/')) {
            final id = int.tryParse(n.split('/').last);
            if (id != null) {
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => _guarded('warehouse', ProductDetailsScreen(productId: id)),
              );
            }
          }
          if (n != null && n.startsWith('/employees/')) {
            final parts = n.split('/').where((p) => p.isNotEmpty).toList();
            // /employees/<id> or /employees/<id>/edit
            if (parts.length >= 2) {
              final id = int.tryParse(parts[1]);
              if (id != null) {
                if (parts.length >= 3 && parts[2] == 'edit') {
                  return MaterialPageRoute<void>(
                    settings: settings,
                    builder: (_) => _guarded('employees', EmployeesEditScreen(id: id)),
                  );
                }
                return MaterialPageRoute<void>(
                  settings: settings,
                  builder: (_) => _guarded('employees', EmployeesViewScreen(id: id)),
                );
              }
            }
          }
          return null;
        },
        routes: {
          '/sales': (_) => _guarded('sales', const SalesScreen()),
          '/arrivals': (_) => _guarded('arrivals', const ArrivalsScreen()),
          '/returns': (_) => _guarded('returns', const ReturnsScreen()),
          '/transfers': (_) => _guarded('transfers', const TransfersScreen()),
          '/warehouse': (_) => _guarded('warehouse', const WarehouseScreen()),
          '/clients': (_) => _guarded('sales', const ClientsScreen()),
          '/debts': (_) => _guarded('debts', const DebtsScreen()),
          '/expenses': (_) => _guarded('expenses', const ExpensesScreen()),
          '/stores': (_) => _guarded('stores', const StoresScreen()),
          '/employees': (_) => _guarded('employees', const EmployeesScreen()),
          '/employees/add': (_) => _guarded('employees', const EmployeesAddScreen()),
          '/tariffs': (_) => _guarded('tariffs', const TariffsScreen()),
          '/course': (_) => _guarded('course', const ExchangeRateScreen()),
          '/reports': (_) => _guarded('reports', const ReportsScreen()),
          '/history': (_) => _guarded('history', const HistoryScreen()),
          '/referral': (_) => _guarded('referral', const ReferralScreen()),
          '/brands': (_) => _guarded('warehouse', const BrandsScreen()),
          '/offline-queue': (_) => const OfflineQueueScreen(),
          '/moderators': (_) => _guarded('employees', const ModeratorsScreen()),
          '/moderators/add': (_) => _guarded('employees', const ModeratorsAddScreen()),
          '/platform': (_) => const PlatformDashboardScreen(),
          '/platform/users': (_) => const PlatformUsersScreen(),
          '/support': (_) => const SupportScreen(),
          '/privacy': (_) => const PrivacyPolicyScreen(),
          '/profile': (_) => _guarded('profile', const ProfileScreen()),
          '/settings/notifications': (_) => _guarded('notifications', const NotificationsSettingsScreen()),
        },
        theme: buildTojirTheme(brightness: Brightness.light),
        darkTheme: buildTojirTheme(
          brightness: Brightness.dark,
          darkSurface: const Color(0xFF0C111C),
        ),
        themeMode: ctx.watch<ThemeController>().mode,
        home: const _SessionGate(),
      ),
    );
  }
}

class _SessionGate extends StatefulWidget {
  const _SessionGate();

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ThemeController>().load();
      context.read<SessionController>().bootstrap();
      bindWebTabResume(() {
        if (!mounted) return;
        context.read<SessionController>().resumeFromBackground();
      });
      if (isIosApp) {
        IapService.instance.init(context.read<ApiClient>());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<SessionController>().resumeFromBackground();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();

    if (!session.isReady) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const SkeletonFeedPage(),
      );
    }

    if (session.bootstrapError != null && !session.isLoggedIn) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(session.bootstrapError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => session.bootstrap(),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!session.isLoggedIn) {
      return const LoginScreen();
    }
    final u = session.user;
    if (u != null && (u['role'] as String?) == 'businessman' && !businessmanHasWarehouse(u)) {
      return const _BusinessmanWarehouseSetupShell();
    }
    return const HomeScreen();
  }
}

/// Бизнесмен без склада: только профиль + один раз диалог «создайте склад».
class _BusinessmanWarehouseSetupShell extends StatefulWidget {
  const _BusinessmanWarehouseSetupShell();

  @override
  State<_BusinessmanWarehouseSetupShell> createState() => _BusinessmanWarehouseSetupShellState();
}

class _BusinessmanWarehouseSetupShellState extends State<_BusinessmanWarehouseSetupShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          title: const Text('Нужен склад'),
          content: const Text(
            'Укажите название и адрес склада в профиле. До этого остальные разделы приложения недоступны — видны только ваши данные после привязки склада.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно')),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const ProfileScreen();
}
