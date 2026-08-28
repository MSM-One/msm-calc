# MSM One – Business Operating System Documentation

Welcome to the complete documentation for **MSM One**. This document is designed to guide you through the project from a beginner's level, explaining what it does, how it is organized, and how it works under the hood.

---

## 1. Project Overview

### What problem does this project solve?
In the steel and manufacturing industry (MSM), calculating rates, managing stock, and booking orders (Sauda) often involves complex math, GST calculations, and manual tracking. **MSM One** automates these processes into a single mobile application. It eliminates manual errors in rate calculations and provides a real-time view of inventory.

### Who is the target audience?
- **Business Owners/Managers**: To monitor stock and book orders.
- **Sales Teams**: To quickly calculate net rates (including GST and freight) for customers.
- **Warehouse/Inventory Staff**: To record stock entries and exits (Stock In/Out).

### Main Objective
To provide a "Business Operating System" that simplifies daily operations like rate calculation, inventory management, and order booking with a professional, easy-to-use interface.

---

## 2. System Architecture

MSM One is a Flutter-based Business Operating System. 

### Backend Architecture
The system backend has been migrated to:
- **Google Sheets (Database)**: Acts as the primary database to store all business data.
- **Google Apps Script (API layer)**: Acts as the intermediary API layer.

**Apps Script responsibilities include:**
- **Dual-Mode Serving**: The script serves both a legacy flat format for web tools and a nested ERP format for the mobile app.
- Reading raw rows from the Google Sheet.
- Grouping data logically (Location → Item → Size).
- Calculating totals for quantities and weights.
- Returning structured JSON data to the Flutter application.
- **CacheService**: Deployed within Apps Script to temporarily store responses, significantly improving API performance and reducing sheet read limitations.

**Main API Endpoint**:
- URL: `https://script.google.com/macros/s/AKfycbzcSBboPXwuH-whwxXe8IdaaTqnTgIPBVo_z1aMJNZuzX2KQq12AL-RjH1znoq3MCex/exec`
- Example usage: `?action=getStock` (for ERP data) or direct call (for legacy data).
- **Root Payload Structure**: The script serves calculations and security data containing:
  - `meta`: Base calculation constants like GST rate, freight, and loading charges.
  - `items`: The core list of materials (e.g., MS Pipe, MS Angle) complete with size-wise dimensions and SD limits.
  - `approved_users`: An array of authenticated Google email addresses permitted to use the app.
  - `users_config`: Dictionary mapping users to their specific roles (e.g., "Admin", "Approved").

### Companion Web Tool: Smart Dispatch Sheet
An interactive web-based tool (`index_delivery.html`) is integrated for generating and printing **MS Delivery Orders**. It connects to the same Apps Script backend to fetch real-time stock and pricing data, providing a specialized interface for warehouse dispatch.


### Real-Time / Auto Refresh
The mobile application is designed to refresh stock data automatically every ~20 seconds.
- **Purpose**: 
  - Ensures near real-time stock visibility across the team.
  - Keeps API loads minimal while guaranteeing data freshness.
  - Provides smooth, non-intrusive UI updates.
- **Manual Refresh**: Users also have the option to trigger a manual refresh from the UI if instant synchronization is needed.

---

## 3. Folder Structure

Here is how the project's codebase is organized.

### Root Folders
- **`android/`, `ios/`, `linux/`, `macos/`, `web/`, `windows/`**: Platform-specific code to allow the app to run on different devices.
- **`assets/`**: Images, icons, and fonts used in the app (e.g., logos and splash screens).
- **`lib/`**: The **heart** of the project where the Dart code resides.

### Important Folders Inside `lib/`
- **`main.dart`**: The entry point of the application managing screens and initial routing.
- **`config/`**:
    - `constants.dart`: Fixed values, default rates, and static size data.
    - `theme.dart`: The "look and feel" of the app (colors, fonts, styles).
- **`engine/`**:
    - `rate_calculator.dart`: The calculating engine containing business math and pricing logic. 
- **`models/`**:
    - `calculator_models.dart`: Blueprints for calculation data (like `ItemEntry` or `SaudaItem`).
    - `stock_models.dart`: Blueprints for ERP inventory data (`StockResponse`, `LocationStock`, `StockItem`, `ItemVariant`).
- **`services/`**:
    - `sheet_service.dart`: Handles bidirectional communication with the Google Apps Script API.
    - `pdf_service.dart`: Handles creating PDF reports for Quotations, Inventory, and Sauda.
    - `export_service.dart`: Handles exporting data to CSV files.
- **`widgets/`**: Small, reusable UI components (custom buttons, cards, inputs).

---

## 4. Stock ERP Module

The stock module has been fundamentally redesigned to follow standard ERP practices. 

### Hierarchy
The inventory follows a strict structural hierarchy:
**LOCATION → ITEM → SIZE → QUANTITY**

**Locations include:**
- Yard
- Factory

### Features
- Location-wise stock visibility.
- Item-wise grouping to organize inventory conceptually.
- Size/specification variants detailing accurate measurements.
- Minimum stock levels for reorder alerts.
- Stock statuses (In Stock / Low Stock / Out of Stock).

### UI Workflow
- **Summary Cards**: Quick visual metrics for Yard Stock, Factory Stock, Grand Total, and Active Items.
- **Primary Action (ENTRY)**: A dedicated entry button serves as the main gateway for recording stock movements, following standard ERP data entry patterns.
- **Search**: Fast searching by item name or size specification.
- **Location Toggle**: Easily switch views between Yard and Factory.
- **Expandable Item Cards**: Clean UI that expands to reveal size-wise breakdowns.
- **Stock Filters**: Quick filtering by stock status and other conditions.


---

## 5. Data Models

The system incorporates robust ERP data models mapping the structured JSON from Apps Script into Flutter Dart objects:

- **`StockResponse`**: The root response containing overall metadata and the list of locations.
- **`LocationStock`**: Represents a physical location (e.g., Yard, Factory) containing its respective items.
- **`StockItem`**: Represents a primary product entity (e.g., MS Pipe, Angle) within a location.
- **`ItemVariant`**: Represents the specific dimensions or sizes under a product, including exact quantity and stock status.

*Data Mapping*: When the Apps Script returns a nested JSON response, the Flutter models use robust parsing logic (e.g., `decodeJsonSafely`) to handle inconsistent type casting. They safely cast `Map<dynamic, dynamic>` to `Map<String, dynamic>` and incorporate fallback values for null safety, ensuring stability even with manual spreadsheet edits.


---

## 6. System Workflow

The complete end-to-end data flow now works as follows:

1. **User opens app**
   ↓
2. **Flutter UI loads**
   ↓
3. **App calls Apps Script API** (`sheet_service.dart` requests data)
   ↓
4. **Apps Script reads Google Sheet** (or serves from CacheService)
   ↓
5. **Data grouped and returned as JSON**
   ↓
6. **Flutter parses JSON into models** (mapping strings to `StockResponse`, `LocationStock`, etc.)
   ↓
7. **UI displays ERP stock structure**

---

## 7. UI Modules

The application is divided into core operational screens:

- **Dashboard**: The central hub providing a high-level summary and rapid access to other modules.
- **Stock Inventory**: The ERP-driven view of all materials, categorized by location, item, and size.
- **Calculator**: The high-speed rate calculation engine for determining complex net rates including GST and freight.
- **Transactions**: (Sauda Booking) The module for recording sales orders, featuring bidirectional **MT ↔ Nos** conversion and standard **Share** functionality for booking details.
- **Smart Dispatch Sheet (Web)**: A companion browser-based tool (`index_delivery.html`) for generating and printing Delivery Orders (DO) with automatic price calculations.
- **Reports**: The document generation hub for exporting data into structured PDFs and CSVs for analysis and sharing.


---

## 8. Implementation Status

### ✅ Completed
- Flutter UI system design and layout.
- ERP stock inventory structure (Location → Item → Size).
- Rate calculator mathematical engine.
- PDF generated reports and CSV exports.
- Google Sign-In authentication integration.
- Google Sheets backend database integration.
- Apps Script API structure and JSON generation.
- **Robust JSON Parsing**: Safe map casting and null-safety handling for API responses.
- **MT ↔ Nos Conversion**: Bidirectional math for Sauda Booking.
- **Smart Dispatch Web Tool**: Delivery Order generation system.

### 🔄 In Progress
- Improving stock auto-refresh logic for background performance.
- Enhancing global error handling across services.
- UI performance and layout improvements (especially on specialized form inputs).
- **Expanded Dispatch Features**: Adding status tracking to the Delivery Order web tool.


### 🚀 Future Roadmap
- **Multi-User Synchronization**: Real-time collaborative updates across multiple devices.
- **Stock Alerts**: Push notifications and internal alerts for low inventory.
- **Analytics Dashboard**: Graphical insights and business trend reports.
- **Offline Mode**: A local database fallback allowing operations without an internet connection.

---

## 9. Simple Business Explanation

**MSM One** can be summarized as:

> *"A digital operating system for a steel trading or manufacturing business that manages stock, calculations, transactions, and reports in one comprehensive platform."*

Think of this app like a **Digital Manager** for a steel shop:
- The **Dashboard** is the manager's desk where they decide what to do.
- The **Calculator** is their high-speed brain for figuring out prices instantly.
- **Stock Inventory** is their digital warehouse system where they track exactly what materials are in the Yard or Factory.
- **Services (PDF/CSV)** act as their assistant, preparing professional reports for clients and internal review.

The project is built using **Flutter**, which allows it to run beautifully on both Android phones and iOS devices seamlessly.

---
*Documentation updated in March 2026, reflecting the transition to a Google Sheets API backend and Full ERP Stock structures.*
