class AppPermissions {
  AppPermissions._();

  // ── Inventory Module ──────────────────────────────────────────────────────
  static const String inventoryScreen = 'inventory.screen';
  static const String stockIn = 'inventory.stock_in';
  static const String stockOut = 'inventory.stock_out';
  static const String stockTransfer = 'inventory.transfer';
  static const String vendorPurchase = 'inventory.vendor_purchase';
  static const String inventoryQuantityView = 'inventory.quantity.view';
  static const String inventoryMetricsView = 'inventory.metrics.view';

  // Re-mapping old keys for compatibility where needed or replacing them
  static const String screensStockInventory = inventoryScreen;
  static const String inventoryView = inventoryScreen;

  // ── Sauda Module ──────────────────────────────────────────────────────────
  static const String saudaView = 'sauda.view';
  static const String saudaCreate = 'sauda.create';
  static const String saudaEdit = 'sauda.edit';
  static const String saudaDelete = 'sauda.delete';

  // ── Reports Module ────────────────────────────────────────────────────────
  static const String reportsScreen = 'reports.screen';
  static const String reportsMovement = 'reports.movement';
  static const String reportsNonMoving = 'reports.non_moving';
  static const String reportsTodaySummary = 'reports.today_summary';
  static const String reportsOverview = 'reports.overview';
  static const String reportsExport = 'reports.export';
  static const String reportsExportExcel = 'reports.export.excel';
  static const String transactionsQuantityView = 'transactions.quantity.view';

  static const String reportStockLedger = 'report_stock_ledger';
  static const String reportLowStock = 'report_low_stock';

  // Re-mapping old keys
  static const String reportsView = reportsScreen;
  static const String screensReports = reportsScreen;

  /// Helper list of all available permission slugs
  static const List<String> allSlugs = [
    inventoryScreen,
    reportsScreen,
    stockIn,
    stockOut,
    stockTransfer,
    ratesView,
    vendorPurchase,
    usersView,
    usersManage,
    usersDelete,
    reportsMovement,
    reportsNonMoving,
    reportsTodaySummary,
    reportStockLedger,
    reportLowStock,
    reportsOverview,
    screensSampleRate,
    screensSalesDocCenter,
    screensMasterSize,
    screensStockSheet,
    canAccessStockSheet,
  ];

  // ── Admin Module ──────────────────────────────────────────────────────────
  static const String usersView = 'users.view';
  static const String usersManage = 'users.manage';
  static const String usersDelete = 'users.delete';
  static const String ratesView = 'financials.rates_view';

  // ── Dashboard ─────────────────────────────────────────────────────────────
  static const String dashboardView = 'dashboard.view';

  // ── Screen Access ─────────────────────────────────────────────────────────
  static const String screensDashboard = 'screens.dashboard';
  static const String screensUsers = 'screens.manage_users';
  static const String screensQuotation = 'screens.quotation';
  static const String screensCalculator = 'screens.calculator';
  static const String screensSaudaBooking = 'screens.sauda_booking';
  static const String screensVendorPurchase = 'screens.vendor_purchase';
  static const String screensSampleRate = 'screens.sample_rate';
  static const String screensSalesDocCenter = 'screens.sales_doc_center';
  static const String screensMasterSize = 'screens.master_size';

  // Stock Sheet Screen Access Slugs
  static const String screensStockSheet = 'screens.stock_sheet';
  static const String canAccessStockSheet = 'can_access_stock_sheet';

  // Refined Inventory Screen Hierarchy
  static const String screensInventoryDash = 'inventory.dashboard';
  static const String screensCurrentStock = 'inventory.current_stock';
  static const String screensTransactions = 'inventory.transactions';
  static const String screensStockDetail = 'inventory.stock_detail';
  static const String screensItemDetail = 'inventory.item_detail';
  static const String screensTxnDetail = 'inventory.txn_detail';
}
