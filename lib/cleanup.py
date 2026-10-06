import os
import re

file_path = 'lib/main.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    code = f.read()

# Make sure imports are added
imports = '''import 'screens/inventory_dashboard_screen.dart';
import 'screens/current_stock_screen.dart';
import 'screens/stock_transaction_screen.dart';
import 'screens/stock_month_report_screen.dart';
import 'screens/main_inventory_shell.dart';
import 'screens/inventory_history_screen.dart';
import 'services/stock_notifier.dart';
'''

if 'screens/inventory_dashboard_screen.dart' not in code:
    code = code.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\\n" + imports, 1)

# we need to remove the stock list of things
to_remove_entities = [
    "class StockDashboardScreen",
    "class _StockDashboardScreenState",
    "class StockTransactionScreen",
    "class _StockTransactionScreenState",
    "class _StockItemBlock",
    "class _StockSizeRow",
    "class CurrentStockScreen",
    "class _CurrentStockScreenState",
    "class StockMonthReportScreen",
    "class _StockMonthReportScreenState",
    "class MainInventoryShell",
    "class _MainInventoryShellState",
    "class CurrentStockModuleScreen",
    "class CurrentStockLocationItemsScreen",
    "class CurrentStockItemDetailsScreen",
    "class TransactionHistoryScreen",
    "class _TransactionHistoryScreenState",
    "Future<Map<String, dynamic>> _buildAvailableStockFromTransactions",
    "String _normalizeStockLocation",
    "final ValueNotifier<int> stockRefreshNotifier",
    "void notifyStockDataChanged"
]

def remove_entity(code, entity_str):
    idx = code.find(entity_str)
    if idx == -1:
        return code # not found
    
    # backtrack to start of line or annotations
    start_idx = idx
    # naive brace counting
    brace_start = code.find('{', idx)
    
    # if it's a field or method not ending in a brace but semicolon:
    if "final ValueNotifier" in entity_str or "void notifyStockDataChanged" in entity_str:
        end_idx = code.find(';', idx)
        if "notifyStockDataChanged" in entity_str:
            brace_start = code.find('{', idx)
            semicolon_idx = code.find(';', idx)
            if brace_start != -1 and (semicolon_idx == -1 or brace_start < semicolon_idx):
                # it's a function with body
                pass
            else:
                return code[:idx] + code[end_idx+1:]
                
    if brace_start == -1:
        return code
        
    stack = 1
    i = brace_start + 1
    while i < len(code) and stack > 0:
        if code[i] == '{':
            stack += 1
        elif code[i] == '}':
            stack -= 1
        i += 1
        
    return code[:start_idx] + code[i:]

for entity in to_remove_entities:
    # Some entities might have annotations above them, but removing just the class is fine, leaving annotations
    # However we might have multiple instances if it's _StockItemBlock (wait, only one hopefully)
    while True:
        old_len = len(code)
        code = remove_entity(code, entity)
        if len(code) == old_len:
            break

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(code)

print("Cleanup script executed.")
